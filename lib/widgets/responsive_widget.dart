import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1440; // optional
  const Breakpoints._();
}

class AppResponsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < Breakpoints.mobile;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= Breakpoints.mobile && w < Breakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.tablet;

  /// Centralized max width for page content; tweak once, applies everywhere.
  static double maxBodyWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= Breakpoints.tablet) return 900; // desktop/tablet center column
    if (w >= Breakpoints.mobile) return 720; // large phones/small tablets
    return double.infinity; // mobile uses full width
  }

  /// Standard page horizontal padding per breakpoint
  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hPad = w >= Breakpoints.tablet ? 24.0 : 16.0;
    return EdgeInsets.symmetric(horizontal: hPad);
  }
}

/// Centers content and constrains the width, with responsive padding.
class MaxWidth extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  const MaxWidth({super.key, required this.child, this.maxWidth, this.padding});

  @override
  Widget build(BuildContext context) {
    final maxW = maxWidth ?? AppResponsive.maxBodyWidth(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(
          padding: padding ?? AppResponsive.pagePadding(context),
          child: child,
        ),
      ),
    );
  }
}

/// A scaffold that automatically centers the body and applies responsive padding.
class ResponsiveScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool useSafeArea;
  final EdgeInsets? padding;
  const ResponsiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.backgroundColor,
    this.useSafeArea = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final content = MaxWidth(padding: padding, child: body);
    final wrapped = useSafeArea ? SafeArea(child: content) : content;
    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      appBar: appBar,
      body: wrapped,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Sliver helper to keep sections centered with the same max width as pages.
class SliverMaxWidth extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  const SliverMaxWidth({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });
  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: MaxWidth(maxWidth: maxWidth, padding: padding, child: child),
    );
  }
}
