import { n as escapeHtml } from "./core-DEy9UQvI.js";
import { c as numLines, i as doc, t as addListener } from "./core-C0HOUBwg.js";
//#region src/utils/local.ts
var scrollToEl = (editor, el, paddingTop = 0) => {
	const style = editor.container.style;
	style.setProperty("--_sp", "var(--pce-scroll-padding, 2ch)");
	style.scrollPaddingBlock = `calc(var(--_sp) + ${paddingTop}px) calc(var(--_sp) + ${isChrome && !el.offsetWidth ? el.offsetHeight : 0}px)`;
	el.scrollIntoView({ block: "nearest" });
	style.scrollPaddingBlock = "";
	style.removeProperty("--_sp");
};
var getLineStart = (text, position) => position ? text.lastIndexOf("\n", position - 1) + 1 : 0;
var getLineEnd = (text, position) => (position = text.indexOf("\n", position)) + 1 ? position : text.length;
var addListener2 = (element, type, listener, options) => {
	addListener(element, type, listener, options);
	return () => element.removeEventListener(type, listener, options);
};
var addTextareaListener = (editor, type, listener, options) => addListener2(editor.textarea, type, listener, options);
var getStyleValue = (el, prop) => parseFloat(getComputedStyle(el)[prop]);
var getPosition = (editor, el) => {
	const rect1 = el.getBoundingClientRect();
	const rect2 = editor.lines[0].getBoundingClientRect();
	return {
		top: rect1.y - rect2.y,
		bottom: rect2.bottom - rect1.bottom,
		left: rect1.x - rect2.x,
		right: rect2.right - rect1.right,
		height: rect1.height
	};
};
var updateNode = (node, text) => {
	if (node.data != text) node.data = text;
};
var voidlessLangs = new Set("xml,rss,atom,jsx,tsx,xquery,xeora,xeoracube,actionscript".split(","));
var voidTags = /^(?:area|base|w?br|col|embed|hr|img|input|link|meta|source|track)$/;
//#endregion
//#region src/utils/index.ts
/**
* If {@link insertText} has been called, this variable stores the editor's selection
* before the call. This variable is set to 0 right before {@link insertText} returns.
* This can therefore be used inside a `beforeinput` handler to determine if
* {@link insertText} fired the event, and if true, get the selection before the call.
*
* Intended for internal use only.
*/
var prevSelection;
/**
* Escapes all regex syntax characters with a backslash and returns the escaped string.
*
* The returned string is not safe inside a character class.
*/
var regexEscape = (str) => str.replace(/[$+?|.^*()[\]{}\\]/g, "\\$&");
/** Returns the string between the position and the previous \n. */
var getLineBefore = (text, position) => text.slice(getLineStart(text, position), position);
/**
* Gets all lines that are at least partially between `start` and `end`.
* @param text Text to search in.
* @param start Start of the selection.
* @param end End of the selection. Defaults to `start`.
* @returns A tuple containing an array of lines, the starting position of the first line,
* and the ending position of the last line.
*/
var getLines = (text, start, end = start) => [
	text.slice(start = getLineStart(text, start), end = getLineEnd(text, end)).split("\n"),
	start,
	end
];
/**
* Searches a full line for a token that matches a selector and contains `position`
* within the specified margins. Tokens are searched in reverse document order which means
* children are searched before their parents.
* @param editor Editor you want to search in.
* @param selector CSS selector for the tokens you want to search for.
* @param marginLeft How far to the left of the token the position can be. Defaults to 0.
* @param marginRight How far to the right of the token the position can be. Defaults to `marginLeft`.
* @param position Position to search in. Defaults to `selectionStart`.
* @returns A span element if one's found or undefined if not.
* @example
* This will return a string token if the cursor
* is at least 1 character inside a string token
* ```javascript
* getClosestToken(editor, '.string', -1)
* ```
*/
var getClosestToken = (editor, selector, marginLeft = 0, marginRight = marginLeft, position = editor.getSelection()[0]) => {
	const value = editor.value;
	const line = editor.lines[numLines(value, 0, position)];
	const walker = doc.createTreeWalker(line, 5);
	let node = walker.lastChild();
	let offset = getLineEnd(value, position) + 1 - position - node.length;
	while (-offset <= marginRight && (node = walker.previousNode())) {
		if (node.lastChild) continue;
		offset -= node.length || 0;
		if (offset <= marginLeft) {
			for (; node != line; node = node.parentNode) if (node.matches?.(selector)) return node;
		}
	}
};
/**
* Gets the current language at a position.
* Useful if you want to run different logic based on the language.
* @param editor Editor to search in.
* @param position Position to search in. Defaults to `selectionStart`.
*/
var getLanguage = (editor, position) => getClosestToken(editor, "[class*=language-]", 0, 0, position)?.className.match(/language-(\S*)/)[1] || editor.options.language;
/**
* Inserts text into the editor (unless it's read-only) while keeping undo/redo history.
* Focuses the `textarea` if it isn't already.
* @param editor Target editor.
* @param text Text to insert.
* @param start Position to start the insertion. Defaults to `selectionStart`.
* @param end Position to end the insertion. Defaults to `start` if specified, else `selectionEnd`.
* @param newCursorStart New starting position for the cursor. Defaults to the end of the inserted text.
* @param newCursorEnd New ending position for the cursor. Defaults to `newCursorStart`.
*/
var insertText = (editor, text, start, end, newCursorStart, newCursorEnd) => {
	if (editor.options.readOnly) return;
	prevSelection = editor.getSelection();
	end ??= start;
	let textarea = editor.textarea;
	let value = editor.value;
	let avoidBug = isChrome && !value[end ?? prevSelection[1]] && /\n$/.test(text) && /^$|\n$/.test(value);
	let removeListener;
	editor.focused || textarea.focus();
	if (start != null) textarea.setSelectionRange(start, end);
	if (newCursorStart != null) removeListener = editor.on("update", () => {
		textarea.setSelectionRange(newCursorStart, newCursorEnd ?? newCursorStart, prevSelection[2]);
		removeListener();
	});
	isWebKit || textarea.dispatchEvent(new InputEvent("beforeinput", { data: text }));
	if (isChrome || isWebKit) {
		if (avoidBug) {
			textarea.selectionEnd--;
			text = text.slice(0, -1);
		}
		if (isWebKit) text += "\n";
		doc.execCommand(text ? "insertHTML" : "delete", false, escapeHtml(text, /</g, "&lt;"));
		if (avoidBug) textarea.selectionStart++;
	} else doc.execCommand(text ? "insertText" : "delete", false, text);
	prevSelection = 0;
};
/**
* Sets the selection for the `textarea` and synchronously runs the selectionChange listeners.
* If you don't want to synchronously run the listeners, use `textarea.setSelectionRange` instead.
* @param editor Editor you want to change the selection of.
* @param start New selectionStart.
* @param end New selectionEnd. Defaults to `start`.
* @param direction New direction.
*/
var setSelection = (editor, start, end = start, direction) => {
	let textarea = editor.textarea;
	let removeHandler = addListener2(textarea, "focus", (e) => {
		let target = e.relatedTarget;
		target ? target.focus() : textarea.blur();
	});
	textarea.setSelectionRange(start, end, direction);
	removeHandler();
	textarea.dispatchEvent(new Event("selectionchange"));
};
var userAgent = doc ? navigator.userAgent : "";
/** Whether the user is on an Apple-based system. */
var isMac = doc ? /Mac|iPhone|iP[ao]d/.test(navigator.platform) : false;
/** Whether the browser is Chromium based. */
var isChrome = /Chrome\//.test(userAgent);
/** Whether the browser uses the WebKit browser engine. */
var isWebKit = !isChrome && /AppleWebKit\//.test(userAgent);
/**
* Returns a 4 bit integer where each bit represents whether
* each modifier is pressed in the order Shift, Meta, Ctrl, Alt.
*
* ```javascript
* e.shiftKey && !e.metaKey && e.ctrlKey && e.altKey
* // is equivalent to
* getModifierCode(e) == 0b1011
* ```
*/
var getModifierCode = (e) => e.altKey + e.ctrlKey * 2 + e.metaKey * 4 + e.shiftKey * 8;
/**
* Adds an overlay by appending the element to the editor's overlays.
* Equivalent to calling `editor.lines[0].append(overlay)`.
* @param editor Editor or code block you want to add an overlay to.
* @param overlay The overlay you want to add.
*/
var addOverlay = (editor, overlay) => editor.lines[0].append(overlay);
/**
* Gets the position of the cursor in the document. It returns a tuple with three numbers:
*
* 1. The line number of the cursor
* 2. The 1-based column of the cursor
* 3. Number of characters selected
*
* @example
* const [line, col, selected] = getDocumentPosition(editor)
*/
var getDocumentPosition = (editor) => {
	let [start, end, dir] = editor.getSelection();
	let pos = dir < "f" ? start : end;
	let value = editor.value;
	let col = 0;
	let chars = 0;
	let tabSize = editor.options.tabSize || 2;
	for (const char of getLineBefore(value, pos)) col += char == "	" ? tabSize - col % tabSize : 1;
	for (const _ of value.slice(start, end)) chars++;
	return [
		editor.activeLine,
		col + 1,
		chars
	];
};
//#endregion
export { voidlessLangs as C, voidTags as S, getLineStart as _, getLineBefore as a, scrollToEl as b, insertText as c, isWebKit as d, prevSelection as f, getLineEnd as g, addTextareaListener as h, getLanguage as i, isChrome as l, setSelection as m, getClosestToken as n, getLines as o, regexEscape as p, getDocumentPosition as r, getModifierCode as s, addOverlay as t, isMac as u, getPosition as v, updateNode as x, getStyleValue as y };

//# sourceMappingURL=utils-Cmdnutew.js.map