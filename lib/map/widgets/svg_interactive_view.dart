import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rtu_mirea_app/map/map.dart';

class SvgInteractiveMap extends StatefulWidget {
  const SvgInteractiveMap({
    super.key,
    required this.svgAssetPath,
    required this.selectedRoomId,
    required this.onRoomSelected,
  });

  final String svgAssetPath;
  final String? selectedRoomId;
  final ValueChanged<RoomModel> onRoomSelected;

  @override
  State<SvgInteractiveMap> createState() => _SvgInteractiveMapState();
}

class _SvgInteractiveMapState extends State<SvgInteractiveMap>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _zoomAnimationController;

  Animation<Matrix4>? _zoomAnimation;
  bool _isInitialScaleSet = false;
  double _initialScale = 1.0;
  Offset _doubleTapPosition = Offset.zero;
  String? _lastFocusedRoomId;
  final List<_TapAnimation> _tapAnimations = <_TapAnimation>[];
  bool _isInteracting = false;
  Timer? _debounceTapTimer;

  @override
  void initState() {
    super.initState();
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
      final Animation<Matrix4>? zoomAnimation = _zoomAnimation;
      if (zoomAnimation != null) {
        _transformationController.value = zoomAnimation.value;
      }
    });
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    _transformationController.dispose();

    for (final _TapAnimation animation in _tapAnimations) {
      animation.controller.dispose();
    }

    _debounceTapTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SvgInteractiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.svgAssetPath != widget.svgAssetPath) {
      _isInitialScaleSet = false;
      _lastFocusedRoomId = null;
    }

    if (oldWidget.selectedRoomId != widget.selectedRoomId) {
      _lastFocusedRoomId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MapState state = context.watch<MapBloc>().state;
    if (state is! MapLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<RoomModel> rooms = state.rooms;
    final Rect? boundingRect = state.boundingRect;
    final Size canvasSize = Size(
      boundingRect?.width ?? 0,
      boundingRect?.height ?? 0,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!_isInitialScaleSet) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitToScreen(constraints);
          });
          _isInitialScaleSet = true;
        }

        final String? selectedRoomId = widget.selectedRoomId;
        if (selectedRoomId != null && _lastFocusedRoomId != selectedRoomId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusSelectedRoom(constraints);
          });
        }

        return GestureDetector(
          onTapDown:
              (TapDownDetails details) => _handleTapDown(details, constraints),
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              InteractiveViewer(
                constrained: false,
                boundaryMargin: const EdgeInsets.all(20000),
                minScale: 0.1,
                maxScale: 50,
                transformationController: _transformationController,
                onInteractionStart: (ScaleStartDetails details) {
                  _zoomAnimationController.stop();
                  setState(() {
                    _isInteracting = true;
                  });
                },
                onInteractionEnd: (ScaleEndDetails details) {
                  _debounceTapTimer?.cancel();
                  _debounceTapTimer = Timer(
                    const Duration(milliseconds: 200),
                    () {
                      if (mounted) {
                        setState(() {
                          _isInteracting = false;
                        });
                      }
                    },
                  );
                },
                child: Stack(
                  children: <Widget>[
                    SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: SvgPicture.asset(
                        widget.svgAssetPath,
                        fit: BoxFit.none,
                        alignment: Alignment.topLeft,
                        allowDrawingOutsideViewBox: true,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RoomsHighlightPainter(
                          rooms,
                          selectedRoomId: widget.selectedRoomId,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ..._tapAnimations.map((_TapAnimation tapAnimation) {
                final Offset screenPos = tapAnimation.position;
                if (screenPos.dx < 0 ||
                    screenPos.dy < 0 ||
                    screenPos.dx > constraints.maxWidth ||
                    screenPos.dy > constraints.maxHeight) {
                  return const SizedBox();
                }

                return Positioned(
                  left: screenPos.dx - 20,
                  top: screenPos.dy - 20,
                  child: FadeTransition(
                    opacity: tapAnimation.animation,
                    child: ScaleTransition(
                      scale: tapAnimation.animation,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _handleTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (_isInteracting) {
      return;
    }

    final MapState state = context.read<MapBloc>().state;
    if (state is! MapLoaded) {
      return;
    }

    final Offset localPos = details.localPosition;
    final Offset tapPos = _transformationController.toScene(localPos);
    final List<RoomModel> containing = state.rooms
        .where((RoomModel room) => room.path.contains(tapPos))
        .toList(growable: false);
    if (containing.isEmpty) {
      return;
    }

    RoomModel? selected;
    double minDist = double.infinity;
    for (final RoomModel room in containing) {
      final Offset center = room.path.getBounds().center;
      final double dist = (center - tapPos).distance;
      if (dist < minDist) {
        minDist = dist;
        selected = room;
      }
    }

    final RoomModel? selectedRoom = selected;
    if (selectedRoom == null) {
      return;
    }

    developer.log('Clicked room: ${selectedRoom.roomId}');
    widget.onRoomSelected(selectedRoom);
    _startTapAnimation(localPos);
    HapticFeedback.selectionClick();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    final Offset focalPointScene = _transformationController.toScene(
      _doubleTapPosition,
    );

    final double nextScale =
        currentScale < _initialScale * 2.5
            ? math.min(currentScale * 2, 50.0)
            : _initialScale;

    final Matrix4 incremental =
        Matrix4.identity()
          ..translate(focalPointScene.dx, focalPointScene.dy)
          ..scale(nextScale / currentScale)
          ..translate(-focalPointScene.dx, -focalPointScene.dy);

    final Matrix4 zoomMatrix = currentMatrix.clone()..multiply(incremental);
    final Matrix4 clampedMatrix = _clampMatrix(zoomMatrix);

    _zoomAnimation = Matrix4Tween(
      begin: currentMatrix,
      end: clampedMatrix,
    ).animate(
      CurvedAnimation(
        parent: _zoomAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _zoomAnimationController.forward(from: 0);
  }

  void _fitToScreen(BoxConstraints constraints) {
    final MapState state = context.read<MapBloc>().state;
    if (state is! MapLoaded) {
      return;
    }

    final Rect? boundingRect = state.boundingRect;
    final double width = boundingRect?.width ?? 0;
    final double height = boundingRect?.height ?? 0;
    if (width <= 0 || height <= 0) {
      return;
    }

    final double scale = math.min(
      constraints.maxWidth / width,
      constraints.maxHeight / height,
    );
    _initialScale = scale;

    final double translateX = (constraints.maxWidth - width * scale) / 2;
    final double translateY = (constraints.maxHeight - height * scale) / 2;

    final Matrix4 matrix =
        Matrix4.identity()
          ..scale(scale, scale)
          ..translate(translateX / scale, translateY / scale);

    developer.log('FitToScreen => scale=$scale, matrix=$matrix');
    _transformationController.value = matrix;
  }

  void _focusSelectedRoom(BoxConstraints constraints) {
    final String? selectedRoomId = widget.selectedRoomId;
    if (selectedRoomId == null) {
      return;
    }

    final MapState state = context.read<MapBloc>().state;
    if (state is! MapLoaded) {
      return;
    }

    RoomModel? selectedRoom;
    for (final RoomModel room in state.rooms) {
      if (room.roomId == selectedRoomId) {
        selectedRoom = room;
        break;
      }
    }

    final RoomModel? room = selectedRoom;
    if (room == null) {
      return;
    }

    final Rect roomBounds = room.path.getBounds();
    final double targetScale = math.min(math.max(_initialScale * 3, 1.0), 50.0);
    final Offset center = roomBounds.center;
    final double translateX =
        constraints.maxWidth / 2 - center.dx * targetScale;
    final double translateY =
        constraints.maxHeight / 2 - center.dy * targetScale;
    final Matrix4 targetMatrix =
        Matrix4.identity()
          ..translate(translateX, translateY)
          ..scale(targetScale, targetScale);

    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: _clampMatrix(targetMatrix),
    ).animate(
      CurvedAnimation(
        parent: _zoomAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _zoomAnimationController.forward(from: 0);
    _lastFocusedRoomId = selectedRoomId;
  }

  Matrix4 _clampMatrix(Matrix4 matrix) {
    double scale = matrix.getMaxScaleOnAxis();
    scale = scale.clamp(0.1, 50.0);

    final double tx = matrix[12].clamp(-20000.0, 20000.0);
    final double ty = matrix[13].clamp(-20000.0, 20000.0);

    return Matrix4.identity()
      ..scale(scale, scale)
      ..setTranslationRaw(tx, ty, 0);
  }

  void _startTapAnimation(Offset screenPos) {
    final AnimationController controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
    );

    final _TapAnimation tapAnimation = _TapAnimation(
      position: screenPos,
      animation: animation,
      controller: controller,
    );

    setState(() {
      _tapAnimations.add(tapAnimation);
    });

    controller.forward();
    controller.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _tapAnimations.remove(tapAnimation);
        });
        controller.dispose();
      }
    });
  }
}

class _RoomsHighlightPainter extends CustomPainter {
  _RoomsHighlightPainter(this.rooms, {required this.selectedRoomId});

  final List<RoomModel> rooms;
  final String? selectedRoomId;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint highlightPaint =
        Paint()
          ..color = Colors.yellow.withOpacity(0.3)
          ..style = PaintingStyle.fill;

    for (final RoomModel room in rooms) {
      if (room.roomId == selectedRoomId) {
        canvas.drawPath(room.path, highlightPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_RoomsHighlightPainter oldDelegate) {
    return oldDelegate.selectedRoomId != selectedRoomId ||
        oldDelegate.rooms.length != rooms.length;
  }
}

class _TapAnimation {
  _TapAnimation({
    required this.position,
    required this.animation,
    required this.controller,
  });

  final Offset position;
  final Animation<double> animation;
  final AnimationController controller;
}
