/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa

struct WorkspaceTheme {

  static let `default` = WorkspaceTheme()

  var foreground = NSColor.black
  var background = NSColor.white

  var separator = NSColor.controlShadowColor

  var barBackground = NSColor.windowBackgroundColor
  var barFocusRing = NSColor.selectedControlColor

  var barButtonBackground = NSColor.clear
  var barButtonHighlight = NSColor.controlShadowColor

  var toolbarForeground = NSColor.darkGray
  var toolbarBackground = NSColor(red: 0.899, green: 0.934, blue: 0.997, alpha: 1)
}