import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Page route used everywhere in jedToolKit.
///
/// iOS: identical to [CupertinoPageRoute] (edge-swipe back included).
///
/// Android: same slide animation, but WITHOUT Flutter's own left-edge swipe
/// recognizer. On Android the system back gesture comes from the same screen
/// edge; when both fire, the Cupertino gesture controller is left half-finished,
/// the Navigator keeps `userGestureInProgress == true` and ignores every touch
/// ("frozen screen"). Letting only the system gesture pop the route avoids that.
class JedPageRoute<T> extends CupertinoPageRoute<T> {
  JedPageRoute({
    required super.builder,
    super.title,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (defaultTargetPlatform == TargetPlatform.iOS || fullscreenDialog) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: false,
      child: child,
    );
  }
}
