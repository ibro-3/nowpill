/// Web/desktop stub for the widget-action background entry point. Only
/// Android launches `widgetActionMain` (from the Kotlin WidgetActionReceiver);
/// the real implementation lives in `widget_action_native.dart` and touches
/// dart:ffi, so it must stay out of the web compilation.
@pragma('vm:entry-point')
void widgetActionMainImpl() {
  // No-op off Android.
}
