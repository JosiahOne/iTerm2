//
//  iTermEditKeyActionWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermEditKeyActionWindowController.h"

#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope.h"
#import "iTermKeyBindingMgr.h"
#import "NSPopUpButton+iTerm.h"
#import "RegexKitLite.h"

@interface iTermEditKeyActionWindowController () <
    iTermShortcutInputViewDelegate>

@property(nonatomic, assign) BOOL ok;

@end

@implementation iTermEditKeyActionWindowController {
    IBOutlet iTermShortcutInputView *_shortcutField;
    IBOutlet NSTextField *_keyboardShortcutLabel;
    IBOutlet NSTextField *_touchBarLabel;
    IBOutlet NSPopUpButton *_actionPopup;
    IBOutlet NSTextField *_parameter;
    IBOutlet NSTextField *_parameterLabel;
    IBOutlet NSPopUpButton *_profilePopup;
    IBOutlet NSPopUpButton *_selectionMovementUnit;
    IBOutlet NSPopUpButton *_menuToSelectPopup;
    IBOutlet NSTextField *_profileLabel;
    IBOutlet NSTextField *_colorPresetsLabel;
    IBOutlet NSPopUpButton *_colorPresetsPopup;
    IBOutlet NSView *_pasteSpecialViewContainer;

    iTermPasteSpecialViewController *_pasteSpecialViewController;
    iTermFunctionCallTextFieldDelegate *_functionCallDelegate;
}

- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context {
    self = [super initWithWindowNibName:@"iTermEditKeyActionWindowController"];
    if (self) {
        _suggestContext = context;
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    for (NSMenuItem *item in [_actionPopup itemArray]) {
        [item setState:NSOffState];
    }
    NSString *formattedString = @"";
    if (self.currentKeyCombination) {
        formattedString = [iTermKeyBindingMgr formatKeyCombination:self.currentKeyCombination];
    }
    _shortcutField.stringValue = formattedString;
    _touchBarLabel.stringValue = self.label ?: @"";
    [_actionPopup selectItemWithTag:self.action];
    [_actionPopup setTitle:[self titleOfActionWithTag:self.action]];
    _parameter.stringValue = self.parameterValue ?: @"";
    if (self.action == KEY_ACTION_SELECT_MENU_ITEM) {
        [[self class] populatePopUpButtonWithMenuItems:_menuToSelectPopup
                                         selectedTitle:[[_menuToSelectPopup selectedItem] title]
                                            identifier:_menuToSelectPopup.selectedItem.identifier];
        NSArray *parts = [self.parameterValue componentsSeparatedByString:@"\n"];
        if (parts.count < 2) {
            [_menuToSelectPopup selectItemWithTitle:self.parameterValue];
        } else {
            NSInteger index = [_menuToSelectPopup.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                return [obj.identifier isEqualToString:parts[1]];
            }];
            if (index == NSNotFound) {
                [_menuToSelectPopup selectItemWithTitle:parts.firstObject];
            } else {
                [_menuToSelectPopup selectItemAtIndex:index];
            }
        }
    }

    _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
    [_pasteSpecialViewController view];

    [self updateViewsAnimated:NO];
    if (!_profilePopup.isHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:self.parameterValue];
    }
    if (!_colorPresetsPopup.isHidden) {
        [_colorPresetsPopup loadColorPresetsSelecting:self.parameterValue];
    }
    if (!_selectionMovementUnit.isHidden) {
        [_selectionMovementUnit selectItemWithTag:[self.parameterValue integerValue]];
    }

    if (self.action == KEY_ACTION_PASTE_SPECIAL ||
        self.action == KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION) {
        [_pasteSpecialViewController loadSettingsFromString:self.parameterValue];
    } else {
        // Set a few defaults; otherwise everything is reasonable.
        _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
        _pasteSpecialViewController.shouldRemoveNewlines = NO;
        _pasteSpecialViewController.shouldBase64Encode = NO;
        _pasteSpecialViewController.shouldWaitForPrompt = NO;
        _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
}

- (NSString *)titleOfActionWithTag:(int)theTag {
    // Can't search for an item with tag 0 using the API, so search manually.
    for (NSMenuItem* anItem in [[_actionPopup menu] itemArray]) {
        if (![anItem isSeparatorItem] && [anItem tag] == theTag) {
            return [anItem title];
            break;
        }
    }
    return @"";
}

- (void)setAction:(int)action {
    if (action == KEY_ACTION_IR_FORWARD) {
        action = KEY_ACTION_IGNORE;
    }
    _action = action;
}

#pragma mark - iTermShortcutInputViewDelegate

// Note: This is called directly by iTermHotKeyController when the action requires key remapping
// to be disabled so the shortcut can be input properly. In this case, |view| will be nil.
- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    self.currentKeyCombination = view.shortcut.identifier;
}

#pragma mark - Private

- (void)updateViewsAnimated:(BOOL)animated {
    int tag = [[_actionPopup selectedItem] tag];
    if (self.isTouchBarItem) {
        _keyboardShortcutLabel.stringValue = @"Touch Bar Label";
        _touchBarLabel.hidden = NO;
        _shortcutField.hidden = YES;
    } else {
        _keyboardShortcutLabel.stringValue = @"Keyboard Shortcut";
        _touchBarLabel.hidden = YES;
        _shortcutField.hidden = NO;
    }

    BOOL parameterHidden = YES;
    BOOL parameterLabelHidden = YES;
    BOOL profilePopupHidden = YES;
    BOOL selectionMovementUnitHidden = YES;
    BOOL profileLabelHidden = YES;
    BOOL menuToSelectPopupHidden = YES;
    BOOL shortcutFieldDisableKeyRemapping = NO;
    BOOL colorPresetsLabelHidden = YES;
    BOOL colorPresetsPopupHidden = YES;
    BOOL pasteSpecialHidden = YES;
    id<NSTextFieldDelegate> parameterDelegate = nil;

    switch (tag) {
        case KEY_ACTION_HEX_CODE:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"ex: 0x7f 0x20"];
            break;

        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_TEXT:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Enter value to send"];
            break;

        case KEY_ACTION_RUN_COPROCESS:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Enter command to run"];
            break;

        case KEY_ACTION_SELECT_MENU_ITEM:
            [[_parameter cell] setPlaceholderString:@"Enter name of menu item"];
            menuToSelectPopupHidden = NO;
            break;

        case KEY_ACTION_ESCAPE_SEQUENCE:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"characters to send"];
            parameterLabelHidden = NO;
            [_parameterLabel setStringValue:@"Esc+"];
            break;

        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            profileLabelHidden = NO;
            profilePopupHidden = NO;
            break;

        case KEY_ACTION_LOAD_COLOR_PRESET:
            [_colorPresetsLabel setHidden:NO];
            [_colorPresetsPopup setHidden:NO];
            break;

        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
            shortcutFieldDisableKeyRemapping = YES;
            [_parameter setStringValue:@""];
            parameterLabelHidden = NO;
            [_parameterLabel setStringValue:@"Modifier remapping disabled: type the actual key combo you want to affect."];
            break;

        case KEY_ACTION_FIND_REGEX:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Regular Expression"];
            break;

        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Function Call"];
            if (!_functionCallDelegate) {
                _functionCallDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:_suggestContext]
                                                                                           passthrough:nil
                                                                                         functionsOnly:YES];
            }
            parameterDelegate = _functionCallDelegate;
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            pasteSpecialHidden = NO;
            break;

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            [_parameter setStringValue:@""];
            selectionMovementUnitHidden = NO;
            break;

        default:
            [_parameter setStringValue:@""];
            break;
    }

    [_parameter setHidden:parameterHidden];
    [_parameterLabel setHidden:parameterLabelHidden];
    [_profilePopup setHidden:profilePopupHidden];
    [_selectionMovementUnit setHidden:selectionMovementUnitHidden];
    [_profileLabel setHidden:profileLabelHidden];
    [_menuToSelectPopup setHidden:menuToSelectPopupHidden];
    _shortcutField.disableKeyRemapping = shortcutFieldDisableKeyRemapping;
    [_colorPresetsLabel setHidden:colorPresetsLabelHidden];
    [_colorPresetsPopup setHidden:colorPresetsPopupHidden];
    [self setPasteSpecialHidden:pasteSpecialHidden];
    _parameter.delegate = parameterDelegate;
    if (!parameterDelegate && _functionCallDelegate) {
        _functionCallDelegate = nil;
    }

    [self updateFrameAnimated:animated];
}

- (BOOL)anyAccessoryVisible {
    return (!_parameter.isHidden ||
            !_profilePopup.isHidden ||
            !_menuToSelectPopup.isHidden ||
            !_colorPresetsPopup.isHidden ||
            !_pasteSpecialViewContainer.isHidden ||
            !_parameterLabel.isHidden ||
            !_selectionMovementUnit.isHidden);
}

- (void)updateFrameAnimated:(BOOL)animated {
    NSRect rect = self.window.frame;
    /*
     *   Side margin                     Side margin
     *   |                               |
     *  |-|                             |-|
     *  +---------------------------------+
     *  |                                 |
     *  |  Keyboard shortcut: [        ]  |
     *  |             Action: [v Popup ]  |  _
     *  |         Basic Accessory         |  _|-- Basic accessory height
     *  |                                 |
     *  |                  [Cancel] [OK]  |
     *  +---------------------------------+
     *     |---------------------------|
     *     Normal width excluding margins
     *
     *  +---------------------------------+  -
     *  |                                 |  |
     *  |  Keyboard shortcut: [        ]  |  |
     *  |             Action: [v Popup ]  |  |-- Height excluding accessory
     *  |                                 |  |
     *  |                   [Cancel] [OK] |  |
     *  +---------------------------------+  -
     *
     */
    const CGFloat heightExcludingAccessory = 126;
    const CGFloat sideMarginWidth = 20;
    const CGFloat basicAccessoryHeight = 31;
    const CGFloat normalWidthExcludingMargins = 402;
    if ([self anyAccessoryVisible]) {
        if (!_pasteSpecialViewContainer.hidden) {
            const CGFloat widthExcludingMargins = MAX(normalWidthExcludingMargins,
                                                      _pasteSpecialViewController.view.frame.size.width);
            rect.size = NSMakeSize(widthExcludingMargins + sideMarginWidth * 2,
                                   _pasteSpecialViewController.view.frame.size.height + heightExcludingAccessory);
        } else {
            rect.size = NSMakeSize(normalWidthExcludingMargins + sideMarginWidth * 2,
                                   heightExcludingAccessory + basicAccessoryHeight);
        }
    } else {
        rect.size = NSMakeSize(normalWidthExcludingMargins + sideMarginWidth * 2,
                               heightExcludingAccessory);
    }
    if (animated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.window setFrame:rect display:YES animate:YES];
        });
    } else {
        [self.window setFrame:rect display:YES animate:NO];
    }
}

- (void)setPasteSpecialHidden:(BOOL)hidden {
    _pasteSpecialViewContainer.hidden = hidden;
}

+ (void)populatePopUpButtonWithMenuItems:(NSPopUpButton *)button
                           selectedTitle:(NSString *)selectedValue
                              identifier:(NSString *)identifier {
    [self recursiveAddMenu:[NSApp mainMenu] toButtonMenu:[button menu] depth:0];
    if (selectedValue) {
        NSMenuItem *theItem = [[button menu] itemWithTitle:selectedValue];
        if (theItem) {
            [button setTitle:selectedValue];
            [theItem setState:NSOnState];
        }
    }
}

+ (BOOL)item:(NSMenuItem *)item isWindowInWindowsMenu:(NSMenu *)menu {
    if (![[menu title] isEqualToString:@"Window"]) {
        return NO;
    }

    return ([item.title isMatchedByRegex:@"^\\d+\\. " ]);
}

+ (void)recursiveAddMenu:(NSMenu *)menu
            toButtonMenu:(NSMenu *)buttonMenu
                   depth:(int)depth{
    for (NSMenuItem* item in [menu itemArray]) {
        if ([item isSeparatorItem]) {
            continue;
        }
        if ([[item title] isEqualToString:@"Services"] ||  // exclude services menu
            [self item:item isWindowInWindowsMenu:menu]) {  // exclude windows in window menu
            continue;
        }
        NSMenuItem *theItem = [[NSMenuItem alloc] init];
        [theItem setTitle:[item title]];
        theItem.identifier = item.identifier;
        [theItem setIndentationLevel:depth];
        if ([item hasSubmenu]) {
            if (depth == 0 && [[buttonMenu itemArray] count]) {
                [buttonMenu addItem:[NSMenuItem separatorItem]];
            }
            [theItem setEnabled:NO];
            [buttonMenu addItem:theItem];
            [self recursiveAddMenu:[item submenu] toButtonMenu:buttonMenu depth:depth + 1];
        } else {
            [buttonMenu addItem:theItem];
        }
    }
}


#pragma mark - Actions

- (IBAction)actionChanged:(id)sender {
    [_actionPopup setTitle:[[sender selectedItem] title]];
    NSString *guid = [[_profilePopup selectedItem] representedObject];
    [_profilePopup populateWithProfilesSelectingGuid:guid];
    [_colorPresetsPopup loadColorPresetsSelecting:_colorPresetsPopup.selectedItem.representedObject];
    [[self class] populatePopUpButtonWithMenuItems:_menuToSelectPopup
                                     selectedTitle:[[_menuToSelectPopup selectedItem] title]
                                        identifier:_menuToSelectPopup.selectedItem.identifier];
    [self updateViewsAnimated:YES];
}


- (IBAction)ok:(id)sender {
    if (self.isTouchBarItem) {
        if (!_touchBarLabel.stringValue.length) {
            NSBeep();
            return;
        }
        self.label = _touchBarLabel.stringValue;
    } else {
        if (!self.currentKeyCombination) {
            NSBeep();
            return;
        }
    }

    self.action = [[_actionPopup selectedItem] tag];

    switch (self.action) {
        case KEY_ACTION_SELECT_MENU_ITEM:
            if (_menuToSelectPopup.selectedItem.identifier.length) {
              self.parameterValue = [NSString stringWithFormat:@"%@\n%@", _menuToSelectPopup.selectedItem.title, _menuToSelectPopup.selectedItem.identifier ?: @""];
            } else {
                self.parameterValue = [[_menuToSelectPopup selectedItem] title];
            }
            break;


        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            self.parameterValue = [[_profilePopup selectedItem] representedObject];
            break;

        case KEY_ACTION_LOAD_COLOR_PRESET:
            self.parameterValue = [[_colorPresetsPopup selectedItem] title];
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            self.parameterValue = [_pasteSpecialViewController stringEncodedSettings];
            break;

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            self.parameterValue = [@(_selectionMovementUnit.selectedTag) description];
            break;

        default:
            self.parameterValue = [_parameter stringValue];
            break;
    }
    self.ok = YES;
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)cancel:(id)sender {
    self.ok = NO;
    [self.window.sheetParent endSheet:self.window];
}

@end
