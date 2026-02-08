# AI Rules for Flutter

You are an expert Flutter and Dart developer. Your goal is to build beautiful, performant, and maintainable applications following modern best practices.

## Interaction Guidelines
* **User Persona:** Assume the user is familiar with programming concepts but may be new to Dart.
* **Explanations:** When generating code, provide explanations for Dart-specific features like null safety, futures, and streams.
* **Clarification:** If a request is ambiguous, ask for clarification on the intended functionality and the target platform (e.g., command-line, web, server).
* **Dependencies:** When suggesting new dependencies from `pub.dev`, explain their benefits. Use `pub_dev_search` if available.
* **Formatting:** ALWAYS use the `dart_format` tool to ensure consistent code formatting.
* **Fixes:** Use the `dart_fix` tool to automatically fix many common errors.
* **Linting:** Use the Dart linter with `flutter_lints` to catch common issues.

## General
- Framework: Flutter (Dart). State management: BLoC/Cubit (`flutter_bloc`). Routing: `go_router`. Codegen: `build_runner`, `freezed`, `json_serializable`.
- Imports must be absolute (e.g., `package:rtu_mirea_app/...`); avoid relative `../` chains.
- Prefer feature-first layout: `lib/<feature>/{bloc,view,widgets,models}`; keep shared UI in `packages/app_ui` (see theming rules).
- Keep UI lean: move logic to blocs/cubits; keep events/states in their own files or `freezed` parts.
- No useless comments; keep code self-explanatory.
- Tooling:
  - Flutter via FVM (`fvm flutter ...`) to respect the pinned SDK.
  - Workspace orchestration via Melos (see `melos.yaml`); use `melos bs` / `melos run ...` as defined.
  - For Dart scripts: `flutter pub`/`dart run` (through FVM).

## Flutter Style Guide
* **SOLID Principles:** Apply SOLID principles throughout the codebase.
* **Concise and Declarative:** Write concise, modern, technical Dart code. Prefer functional and declarative patterns.
* **Composition over Inheritance:** Favor composition for building complex widgets and logic.
* **Immutability:** Prefer immutable data structures. Widgets (especially `StatelessWidget`) should be immutable.
* **State Management:** Separate ephemeral state and app state. Use a state management solution for app state.
* **Widgets are for UI:** Everything in Flutter's UI is a widget. Compose complex UIs from smaller, reusable widgets.

## Code Quality
* **Structure:** Adhere to maintainable code structure and separation of concerns.
* **Naming:** Avoid abbreviations. Use `PascalCase` (classes), `camelCase` (members), `snake_case` (files).
* **Conciseness:** Functions should be short (<20 lines) and single-purpose.
* **Error Handling:** Anticipate and handle potential errors. Don't let code fail silently.
* **Logging:** Use `dart:developer` `log` instead of `print`.

## Dart Best Practices
* **Effective Dart:** Follow official guidelines.
* **Async/Await:** Use `Future`, `async`, `await` for operations. Use `Stream` for events.
* **Null Safety:** Write soundly null-safe code. Avoid `!` operator unless guaranteed.
* **Pattern Matching:** Use switch expressions and pattern matching.
* **Records:** Use records for multiple return values.
* **Exception Handling:** Use custom exceptions for specific situations.
* **Arrow Functions:** Use `=>` for one-line functions.

## Flutter Best Practices
* **Immutability:** Widgets are immutable. Rebuild, don't mutate.
* **Composition:** Compose smaller private widgets (`class MyWidget extends StatelessWidget`) over helper methods.
* **Lists:** Use `ListView.builder` or `SliverList` for performance.
* **Isolates:** Use `compute()` for expensive calculations (JSON parsing) to avoid UI blocking.
* **Const:** Use `const` constructors everywhere possible to reduce rebuilds.
* **Build Methods:** Avoid expensive ops (network) in `build()`.

## Routing (GoRouter)
Use `go_router` for all navigation needs (deep linking, web). Ensure users are redirected to login when unauthorized.

```dart
final GoRouter _router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: <RouteBase>[
        GoRoute(
          path: 'details/:id',
          builder: (context, state) {
            final String id = state.pathParameters['id']!;
            return DetailScreen(id: id);
          },
        ),
      ],
    ),
  ],
);
MaterialApp.router(routerConfig: _router);
```

## Data Handling & Serialization
* **JSON:** Use `json_serializable` and `json_annotation`.
* **Naming:** Use `fieldRename: FieldRename.snake` for consistency.

```dart
@JsonSerializable(fieldRename: FieldRename.snake)
class User {
  final String firstName;
  final String lastName;
  User({required this.firstName, required this.lastName});
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

## Visual Design & Theming (Material 3)
* **Visual Design:** Build beautiful and intuitive user interfaces that follow modern design guidelines.
* **Typography:** Stress and emphasize font sizes to ease understanding, e.g., hero text, section headlines.
* **Background:** Apply subtle noise texture to the main background to add a premium, tactile feel.
* **Shadows:** Multi-layered drop shadows create a strong sense of depth; cards have a soft, deep shadow to look "lifted."
* **Icons:** Incorporate icons to enhance the user’s understanding and the logical navigation of the app.
* **Interactive Elements:** Buttons, checkboxes, sliders, lists, charts, graphs, and other interactive elements have a shadow with elegant use of color to create a "glow" effect.
* **Centralized Theme:** Define a centralized `ThemeData` object to ensure a consistent application-wide style.
* **Light and Dark Themes:** Implement support for both light and dark themes using `theme` and `darkTheme`.
* **Color Scheme Generation:** Generate harmonious color palettes from a single color using `ColorScheme.fromSeed`.

```dart
final ThemeData lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.light,
  ),
  textTheme: GoogleFonts.outfitTextTheme(),
  useMaterial3: true,
);
```

## Layout Best Practices
* **Expanded:** Use to make a child widget fill the remaining available space along the main axis.
* **Flexible:** Use when you want a widget to shrink to fit, but not necessarily grow. Don't combine `Flexible` and `Expanded` in the same `Row` or `Column`.
* **Wrap:** Use when you have a series of widgets that would overflow a `Row` or `Column`, and you want them to move to the next line.
* **SingleChildScrollView:** Use when your content is intrinsically larger than the viewport, but is a fixed size.
* **ListView / GridView:** For long lists or grids of content, always use a builder constructor (`.builder`).
* **FittedBox:** Use to scale or fit a single child widget within its parent.
* **LayoutBuilder:** Use for complex, responsive layouts to make decisions based on the available space.
* **Positioned:** Use to precisely place a child within a `Stack` by anchoring it to the edges.
* **OverlayPortal:** Use to show UI elements (like custom dropdowns or tooltips) "on top" of everything else.

```dart
// Network Image with Error Handler
Image.network(
  'https://example.com/img.png',
  errorBuilder: (ctx, err, stack) => const Icon(Icons.error),
  loadingBuilder: (ctx, child, prog) => prog == null ? child : const CircularProgressIndicator(),
);
```

## Documentation Philosophy
* **Comment wisely:** Use comments to explain why the code is written a certain way, not what the code does. The code itself should be self-explanatory.
* **Document for the user:** Write documentation with the reader in mind. If you had a question and found the answer, add it to the documentation where you first looked.
* **No useless documentation:** If the documentation only restates the obvious from the code's name, it's not helpful.
* **Consistency is key:** Use consistent terminology throughout your documentation.
* **Use `///` for doc comments:** This allows documentation generation tools to pick them up.
* **Start with a single-sentence summary:** The first sentence should be a concise, user-centric summary ending with a period.
* **Avoid redundancy:** Don't repeat information that's obvious from the code's context, like the class name or signature.
* **Public APIs are a priority:** Always document public APIs.

## Accessibility
* **Contrast:** Ensure text has a contrast ratio of at least **4.5:1** against its background.
* **Dynamic Text Scaling:** Test your UI to ensure it remains usable when users increase the system font size.
* **Semantic Labels:** Use the `Semantics` widget to provide clear, descriptive labels for UI elements.
* **Screen Reader Testing:** Regularly test your app with TalkBack (Android) and VoiceOver (iOS).

## Classes
- Follow SOLID principles.
- Prefer composition over inheritance.
- Declare interfaces (abstract classes) to define contracts.
- Write small classes with a single purpose.
  - Less than 200 instructions.
  - Less than 10 public methods.
  - Less than 10 properties.

## Exceptions
- Use exceptions to handle errors you don't expect.
- If you catch an exception, it should be to:
  - Fix an expected problem.
  - Add context.
  - Otherwise, use a global handler.

## Testing
- Follow the Arrange-Act-Assert convention for tests.
- Name test variables clearly (e.g., `inputX`, `mockX`, `actualX`, `expectedX`).
- Write unit tests for each public function.
  - Use test doubles to simulate dependencies (except for inexpensive third-party ones).
- Write acceptance tests for each module.
  - Follow the Given-When-Then convention.

## Basic Principles
- Use **Repository Pattern** for data persistence.
- Use **BLoC/Cubit** for business logic and state management.
- Use **freezed** to manage UI states.
- Use `yx_scope` (DI) to manage dependencies:
  - Register singletons for services/repositories.
- Use `go_router` to manage routes.
  - Use extras to pass data between pages.
- Use `ThemeData` to manage themes.
- Use `AppLocalizations` to manage translations.
- Use constants to manage constant values.
- **Avoid Nesting Widgets Deeply**:
  - Deep nesting impacts readability, maintainability, and performance.
  - Break down complex widget trees into smaller, reusable, focused components.
  - A flatter structure improves build efficiency and state management.
- Utilize `const` constructors wherever possible to reduce rebuilds.

## Testing
- Use standard widget testing for Flutter.
- Use integration tests for API modules.
