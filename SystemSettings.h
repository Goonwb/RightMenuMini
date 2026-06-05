/*
 * SystemSettings.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class SystemSettingsApplication, SystemSettingsDocument, SystemSettingsWindow, SystemSettingsPane, SystemSettingsAnchor;

enum SystemSettingsSaveOptions {
	SystemSettingsSaveOptionsYes = 'yes ' /* Save the file. */,
	SystemSettingsSaveOptionsNo = 'no  ' /* Do not save the file. */,
	SystemSettingsSaveOptionsAsk = 'ask ' /* Ask the user whether or not to save the file. */
};
typedef enum SystemSettingsSaveOptions SystemSettingsSaveOptions;

enum SystemSettingsPrintingErrorHandling {
	SystemSettingsPrintingErrorHandlingStandard = 'lwst' /* Standard PostScript error handling */,
	SystemSettingsPrintingErrorHandlingDetailed = 'lwdt' /* print a detailed report of PostScript errors */
};
typedef enum SystemSettingsPrintingErrorHandling SystemSettingsPrintingErrorHandling;

@protocol SystemSettingsGenericMethods

- (void) closeSaving:(SystemSettingsSaveOptions)saving savingIn:(NSURL *)savingIn;  // Close a document.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.

@end



/*
 * Standard Suite
 */

// The application's top-level scripting object.
@interface SystemSettingsApplication : SBApplication

- (SBElementArray<SystemSettingsDocument *> *) documents;
- (SBElementArray<SystemSettingsWindow *> *) windows;

@property (copy, readonly) NSString *name;  // The name of the application.
@property (readonly) BOOL frontmost;  // Is this the active application?
@property (copy, readonly) NSString *version;  // The version number of the application.

- (id) open:(id)x;  // Open a document.
- (void) print:(id)x withProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) quitSaving:(SystemSettingsSaveOptions)saving;  // Quit the application.
- (BOOL) exists:(id)x;  // Verify that an object exists.

@end

// A document.
@interface SystemSettingsDocument : SBObject <SystemSettingsGenericMethods>

@property (copy, readonly) NSString *name;  // Its name.
@property (readonly) BOOL modified;  // Has it been modified since the last save?
@property (copy, readonly) NSURL *file;  // Its location on disk, if it has one.


@end

// A window.
@interface SystemSettingsWindow : SBObject <SystemSettingsGenericMethods>

@property (copy, readonly) NSString *name;  // The title of the window.
- (NSInteger) id;  // The unique identifier of the window.
@property NSInteger index;  // The index of the window, ordered front to back.
@property NSRect bounds;  // The bounding rectangle of the window.
@property (readonly) BOOL closeable;  // Does the window have a close button?
@property (readonly) BOOL miniaturizable;  // Does the window have a minimize button?
@property BOOL miniaturized;  // Is the window minimized right now?
@property (readonly) BOOL resizable;  // Can the window be resized?
@property BOOL visible;  // Is the window visible right now?
@property (readonly) BOOL zoomable;  // Does the window have a zoom button?
@property BOOL zoomed;  // Is the window zoomed right now?
@property (copy, readonly) SystemSettingsDocument *document;  // The document whose contents are displayed in the window.


@end



/*
 * System Settings
 */

// The System Settings top-level scripting object.
@interface SystemSettingsApplication (SystemSettings)

- (SBElementArray<SystemSettingsPane *> *) panes;

@property (copy) SystemSettingsPane *currentPane;  // The currently selected pane.
@property (copy, readonly) SystemSettingsWindow *settingsWindow;  // The main settings window.
@property BOOL showAll;  // Is System Settings in show-all view? (Setting to false does nothing.) Deprecated: setting this property no longer does anything; it is always set to true.

@end

// A settings pane.
@interface SystemSettingsPane : SBObject <SystemSettingsGenericMethods>

- (SBElementArray<SystemSettingsAnchor *> *) anchors;

- (NSString *) id;  // The id of the settings pane.
@property (copy, readonly) NSString *name;  // The name of the settings pane.

- (id) reveal;  // Reveals a settings pane or an anchor within a pane.
- (SystemSettingsPane *) authorize;  // Prompt for authorization for a settings pane. Deprecated: no longer does anything.

@end

// An anchor within a settings pane.
@interface SystemSettingsAnchor : SBObject <SystemSettingsGenericMethods>

@property (copy, readonly) NSString *name;  // The name of the anchor.

- (id) reveal;  // Reveals a settings pane or an anchor within a pane.

@end

