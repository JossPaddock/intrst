import 'package:flutter/material.dart';
import 'dart:html' as html;

class GeneralUtility {
  bool isMobileBrowser(BuildContext context) {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    bool isMobileUserAgent = userAgent.contains('iphone') ||
        userAgent.contains('android') ||
        userAgent.contains('ipad') ||
        userAgent.contains('mobile');

    //optionally do this as well.. mileage may vary
    bool isSmallScreen = MediaQuery.of(context).size.width < 800 ||
        MediaQuery.of(context).size.height < 800;

    return isMobileUserAgent && isSmallScreen;
  }
}
