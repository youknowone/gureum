//
//  CIMInputReceiver.swift
//  OSX
//
//  Created by Jeong YunWon on 21/10/2018.
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import InputMethodKit

public class CIMInputReceiver: NSObject, CIMInputTextDelegate {
    var inputClient: IMKTextInput & IMKUnicodeTextInput
    var composer: CIMComposer
    var controller: CIMInputController

    var hasSelectionRange: Bool = false

    init(server: IMKServer, delegate: Any!, client: IMKTextInput & IMKUnicodeTextInput, controller: CIMInputController) {
        dlog(DEBUG_INPUTCONTROLLER, "**** NEW INPUT CONTROLLER INIT **** WITH SERVER: %@ / DELEGATE: %@ / CLIENT: %@", server, (delegate as? NSObject) ?? "(nil)", (client as? NSObject) ?? "(nil)")
        composer = GureumComposer()
        inputClient = client
        self.controller = controller
    }

    // IMKServerInput 프로토콜에 대한 공용 핸들러
    func input(controller: CIMInputController, inputText string: String?, key keyCode: Int, modifiers flags: NSEvent.ModifierFlags, client sender: Any) -> CIMInputTextProcessResult {
        dlog(DEBUG_LOGGING, "LOGGING::KEY::(%@)(%ld)(%lu)", string?.replacingOccurrences(of: "\n", with: "\\n") ?? "(nil)", keyCode, flags.rawValue)

        let hadComposedString = !_internalComposedString.isEmpty
        let handled = composer.server.input(controller: controller, inputText: string, key: keyCode, modifiers: flags, client: sender)

        composer.server.inputting = true

        switch handled {
        case .notProcessed:
            break
        case .processed:
            break
        case .notProcessedAndNeedsCancel:
            cancelComposition()
        case .notProcessedAndNeedsCommit:
            cancelComposition()
            commitComposition(sender)
            return handled
        default:
            dlog(true, "WRONG RESULT: %d", handled.rawValue)
            assert(false)
        }

        let commited = commitComposition(sender) // 조합 된 문자 반영
        let hasComposedString = !_internalComposedString.isEmpty
        let selectionRange = controller.selectionRange()
        hasSelectionRange = selectionRange.location != NSNotFound && selectionRange.length > 0
        if commited || controller.selectionRange().length > 0 || hadComposedString || hasComposedString {
            updateComposition() // 조합 중인 문자 반영
        }

        composer.server.inputting = false

        dlog(DEBUG_INPUTCONTROLLER, "*** End of Input handling ***")
        return handled
    }
}

extension CIMInputReceiver { // IMKServerInput
    // Committing a Composition
    // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
    func commitComposition(_ sender: Any) -> Bool {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::COMMIT-INTERNAL")
        return commitCompositionEvent(sender)
    }

    func updateComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::UPDATE-INTERNAL")
        controller.updateComposition()
    }

    func cancelComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL-INTERNAL")
        controller.cancelComposition()
    }

    // Committing a Composition
    // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
    func commitCompositionEvent(_ sender: Any!) -> Bool {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::COMMIT")
        if !composer.server.inputting {
            // 입력기 외부에서 들어오는 커밋 요청에 대해서는 편집 중인 글자도 커밋한다.
            dlog(DEBUG_INPUTCONTROLLER, "-- CANCEL composition because of external commit request from %@", sender as! NSObject)
            dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL-INTERNAL")
            cancelCompositionEvent()
        }
        // 왠지는 모르겠지만 프로그램마다 동작이 달라서 조합을 반드시 마쳐주어야 한다
        // 터미널과 같이 조합중에 리턴키 먹는 프로그램은 조합 중인 문자가 없고 보통은 있다
        let commitString = composer.dequeueCommitString()

        // 커밋할 문자가 없으면 중단
        if commitString.isEmpty {
            return false
        }

        dlog(DEBUG_INPUTCONTROLLER, "** CIMInputController -commitComposition: with sender: %@ / strings: %@", sender as! NSObject, commitString)
        let range = controller.selectionRange()
        dlog(DEBUG_LOGGING, "LOGGING::COMMIT::%lu:%lu:%@", range.location, range.length, commitString)
        if range.length > 0 {
            controller.client().insertText(commitString, replacementRange: range)
        } else {
            controller.client().insertText(commitString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }

        composer.server.controllerDidCommit(controller)

        return true
    }

    func updateCompositionEvent() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::UPDATE")
        dlog(DEBUG_INPUTCONTROLLER, "** CIMInputController -updateComposition")
    }

    func cancelCompositionEvent() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL")
        composer.cancelComposition()
    }

    var _internalComposedString: String {
        return composer.composedString
    }

    // Getting Input Strings and Candidates
    // 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
    public override func composedString(_: Any) -> Any {
        let string = _internalComposedString
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::COMPOSEDSTRING::(%@)", string)
        dlog(DEBUG_INPUTCONTROLLER, "** CIMInputController -composedString: with return: '%@'", string)
        return string
    }

    public override func originalString(_: Any!) -> NSAttributedString {
        dlog(DEBUG_INPUTCONTROLLER, "** CIMInputController -originalString:")
        let s = NSAttributedString(string: composer.originalString)
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::ORIGINALSTRING::%@", s.string)
        return s
    }

    public override func candidates(_: Any!) -> [Any]! {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATES")
        return composer.candidates
    }

    func candidateSelected(_ candidateString: NSAttributedString) {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATESELECTED::%@", candidateString)
        composer.server.inputting = true
        composer.candidateSelected(candidateString)
        commitComposition(inputClient)
        composer.server.inputting = false
    }

    func candidateSelectionChanged(_ candidateString: NSAttributedString, controller _: CIMInputController) {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATESELECTIONCHANGED::%@", candidateString)
        composer.candidateSelectionChanged(candidateString)
        updateComposition()
    }
}

extension CIMInputReceiver { // IMKStateSetting
    //! @brief  마우스 이벤트를 잡을 수 있게 한다.
    func recognizedEvents(_: Any!) -> Int {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::RECOGNIZEDEVENTS")
        // NSFlagsChangeMask는 -handleEvent: 에서만 동작

        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue | NSEvent.EventTypeMask.leftMouseDown.rawValue | NSEvent.EventTypeMask.rightMouseDown.rawValue | NSEvent.EventTypeMask.leftMouseDragged.rawValue | NSEvent.EventTypeMask.rightMouseDragged.rawValue)
    }

    //! @brief 자판 전환을 감지한다.
    func setValue(_ value: Any, forTag tag: Int, client sender: Any, controller: CIMInputController) {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CHANGE-%lu-%@", tag, value as? String ?? "(nonstring)")
        dlog(DEBUG_INPUTCONTROLLER, "** CIMInputController -setValue:forTag:client: with value: %@ / tag: %lx / client: %@", value as? String ?? "(nonstring)", tag, String(describing: controller.client as AnyObject))
        if let sender = sender as? IMKTextInput {
            sender.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        }
        switch tag {
        case kTextServiceInputModePropertyTag:
            guard let value = value as? String else {
                NSLog("Failed to change keyboard layout")
                assert(false)
                break
            }
            if value != composer.inputMode {
                commitComposition(sender)
                composer.inputMode = value
            }
        default:
            dlog(true, "**** UNKNOWN TAG %ld !!! ****", tag)
        }

        return
        
        // 미국자판으로 기본자판 잡는 것도 임시로 포기
        /*
        TISInputSource *mainSource = _USSource();
        NSString *mainSourceID = mainSource.identifier;
        TISInputSource *currentSource = [TISInputSource currentSource];
        dlog(1, @"current source: %@", currentSource);
        
        [TISInputSource setInputMethodKeyboardLayoutOverride:mainSource];
        
        TISInputSource *override = [TISInputSource inputMethodKeyboardLayoutOverride];
        if (override == nil) {
            dlog(1, @"override fail");
            TISInputSource *currentASCIISource = [TISInputSource currentASCIICapableLayoutSource];
            dlog(1, @"ascii: %@", currentASCIISource);
            id ASCIISourceID = currentASCIISource.identifier;
            if (![ASCIISourceID isEqualToString:mainSourceID]) {
                dlog(1, @"id: %@ != %@", ASCIISourceID, mainSourceID);
                BOOL mainSourceIsEnabled = mainSource.enabled;
                //if (!mainSourceIsEnabled) {
                //    [mainSource enable];
                //}
                if (mainSourceIsEnabled) {
                    [mainSource select];
                    [currentSource select];
                }
                //if (!mainSourceIsEnabled) {
                //    [mainSource disable];
                //}
            }
        } else {
            dlog(1, @"overrided");
        }
         */
    }
}
