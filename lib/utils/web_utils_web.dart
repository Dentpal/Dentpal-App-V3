// Web implementation using dart:html
import 'dart:html' as html;

String getCurrentPathImpl() => html.window.location.pathname ?? '/';