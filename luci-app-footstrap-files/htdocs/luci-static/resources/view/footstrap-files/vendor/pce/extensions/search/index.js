import { c as numLines, i as doc, l as preventDefault, r as createTemplate, t as addListener } from "../../core-C0HOUBwg.js";
import { _ as getLineStart, a as getLineBefore, d as isWebKit, g as getLineEnd, p as regexEscape, s as getModifierCode, t as addOverlay, u as isMac, x as updateNode, y as getStyleValue } from "../../utils-Cmdnutew.js";
import { s as mod } from "../../utils-ChVWFtO9.js";
import { t as createSearchAPI } from "../../search-CvZenEEf.js";
import { t as createReplaceAPI } from "../../replace-BGouct-V.js";
import { n as highlightSelectionMatches, t as highlightCurrentWord } from "../../selection-ClP9zgI_.js";
//#region src/extensions/search/widget.ts
var shortcut = ` (Alt+${isMac ? "Cmd+" : ""}`;
var template = /* @__PURE__ */ createTemplate(`<div class=prism-search-container style=display:flex;align-items:flex-start;justify-content:flex-end><div dir=ltr class=prism-search><button type=button aria-expanded=false title="Toggle Replace" class=pce-expand></button><div spellcheck=false><div><div class="pce-input pce-find"><input autocorrect=off autocapitalize=off placeholder=Find aria-label=Find><button type=button class=pce-prev title="Previous Match (Shift+Enter)"></button><button type=button class=pce-next title="Next Match (Enter)"></button><div class=search-error></div></div><button type=button class=pce-close title="Close (Esc)"></button></div><div class="pce-input pce-replace"><input autocorrect=off autocapitalize=off placeholder=Replace aria-label=Replace><button type=button title=(Enter)>Replace</button><button type=button title=(${isMac ? "Cmd" : "Ctrl+Alt"}+Enter)>All</button></div><div class=pce-options><div class=pce-match-count>0<span> of </span>0</div><button type=button aria-pressed=false class=pce-regex title="RegExp Search${shortcut}R)"><span aria-hidden=true></span></button><button type=button aria-pressed=false title="Preserve Case${shortcut}P)"><span aria-hidden=true>Aa</span></button><button type=button aria-pressed=false class=pce-whole title="Match Whole Word${shortcut}W)"><span aria-hidden=true>ab</span></button><button type=button aria-pressed=false class=pce-in-selection title="Find in Selection${shortcut}L)">`);
var toggleAttr = (el, name) => el.setAttribute(name, el.getAttribute(name) == "false");
/**
* Extension that adds a widget for search and replace functionality.
* This extension needs styles from `prism-code-editor/search.css`.
*
* Once added to an editor the widget can be opened/closed programmatically with the
* `editor.extensions.searchWidget` object.
*/
var searchWidget = () => {
	let prevLength;
	let useRegExp;
	let matchCase;
	let wholeWord;
	let searchSelection;
	let isOpen;
	let currentSelection;
	let prevUserSelection;
	let prevMargin;
	let selectNext = false;
	let marginTop;
	const self = (editor) => {
		editor.extensions.searchWidget = self;
		const { textarea, wrapper, container, getSelection } = editor;
		const replaceAPI = createReplaceAPI(editor);
		const startSearch = (selectMatch) => {
			if (selectMatch && !isWebKit) textarea.setSelectionRange(...prevUserSelection);
			const error = replaceAPI.search(findInput.value, matchCase, wholeWord, useRegExp, searchSelection);
			const index = error ? -1 : selectNext ? replaceAPI.next() : replaceAPI.closest();
			updateNode(current, index + 1);
			updateNode(total, replaceAPI.matches.length);
			findContainer.classList.toggle("pce-error", !!error);
			if (error) errorEl.textContent = error;
			else if (selectMatch || selectNext) replaceAPI.selectMatch(index, prevMargin);
		};
		const open = (focusInput = true) => {
			if (!isOpen) {
				isOpen = true;
				if (marginTop == null) prevMargin = marginTop = getStyleValue(wrapper, "marginTop");
				prevUserSelection = getSelection();
				addOverlay(editor, searchContainer);
				updateMargin();
				resize();
				observer?.observe(container);
			}
			if (focusInput) findInput.select();
		};
		const close = self.close = (focusTextarea = true) => {
			if (isOpen) {
				isOpen = false;
				replaceAPI.stopSearch();
				searchContainer.remove();
				updateMargin();
				observer?.disconnect();
				focusTextarea && textarea.focus();
			}
		};
		const move = (next) => {
			if (replaceAPI.matches[0]) {
				const index = replaceAPI[next ? "next" : "prev"]();
				replaceAPI.selectMatch(index, prevMargin);
				updateNode(current, index + 1);
			}
		};
		const updateMargin = () => {
			const newMargin = isOpen ? getStyleValue(search, "top") + getStyleValue(search, "height") : marginTop;
			const newScroll = container.scrollTop + newMargin - prevMargin;
			wrapper.style.marginTop = isOpen ? newMargin + "px" : "";
			container.scrollTop = newScroll;
			prevMargin = newMargin;
		};
		const resize = () => div.style.setProperty("--search-width", `min(${container.clientWidth - 2}px - 2.4em - var(--padding-left),20em)`);
		const observer = window.ResizeObserver && new ResizeObserver(resize);
		const replace = () => {
			selectNext = true;
			const index = replaceAPI.replace(replaceInput.value);
			if (index != null) {
				updateNode(current, index + 1);
				replaceAPI.selectMatch(index, prevMargin);
			}
			selectNext = false;
		};
		const replaceAll = () => {
			replaceAPI.replaceAll(replaceInput.value);
		};
		const keyCodeButtonMap = {
			80: matchCaseEl,
			87: wholeWordEl,
			82: useRegExpEl,
			76: inSelectionEl
		};
		const elementHandlerMap = /* @__PURE__ */ new Map([
			[nextEl, () => move(true)],
			[prevEl, move],
			[closeEl, close],
			[replaceEl, replace],
			[replaceAllEl, replaceAll],
			[toggle, () => {
				toggleAttr(toggle, "aria-expanded");
				updateMargin();
			}],
			[matchCaseEl, () => matchCase = !matchCase],
			[useRegExpEl, () => useRegExp = !useRegExp],
			[wholeWordEl, () => wholeWord = !wholeWord],
			[inSelectionEl, () => {
				const value = editor.value;
				if (searchSelection) searchSelection = void 0;
				else {
					searchSelection = getSelection().slice(0, 2);
					if (numLines(value, ...searchSelection) > 1) searchSelection = [getLineStart(value, searchSelection[0]), getLineEnd(value, searchSelection[1])];
				}
				prevLength = value.length;
			}]
		]);
		const getSelectedWord = (selectionOnly) => {
			let [start, end] = getSelection();
			let value = editor.value;
			let word = value.slice(start, end) || (selectionOnly ? "" : /[_\p{N}\p{L}]*$/u.exec(getLineBefore(value, start))[0] + /^[_\p{N}\p{L}]*/u.exec(value.slice(start))[0]);
			return word.includes("\n") ? "" : useRegExp ? regexEscape(word) : word;
		};
		addListener(wrapper, "keydown", (e) => {
			const code = getModifierCode(e);
			const keyCode = e.keyCode;
			const isF3 = keyCode == 114;
			if (keyCode == 70 && code == mod) {
				preventDefault(e);
				open();
				let word = getSelectedWord();
				if (word) {
					doc.execCommand("insertText", false, word);
					findInput.select();
				} else startSearch();
			} else if ((isF3 || keyCode == 71) && (code & 7) == (isF3 ? 0 : mod)) {
				preventDefault(e);
				open(false);
				findInput.value ||= getSelectedWord();
				startSearch();
				move(code < 8);
			} else if (isMac ? code == 5 && keyCode == 70 : code == 2 && keyCode == 72) {
				const searchTerm = getSelectedWord(true);
				const target = e.target;
				const shouldSearch = searchTerm && target != findInput && target != replaceInput;
				const newTarget = target == findInput || shouldSearch ? replaceInput : findInput;
				preventDefault(e);
				open(false);
				if (toggle.getAttribute("aria-expanded") != "true") toggle.click();
				if (shouldSearch) {
					findInput.value = searchTerm;
					startSearch();
				}
				newTarget.focus();
				newTarget.select();
			}
		});
		addListener(textarea, "beforeinput", () => {
			if (isOpen && searchSelection) currentSelection = getSelection();
		});
		editor.on("update", () => {
			if (!isOpen) return;
			if (searchSelection && currentSelection) {
				const diff = prevLength - (prevLength = editor.value.length);
				const end = currentSelection[1];
				if (end <= searchSelection[1]) {
					searchSelection[1] -= diff;
					if (end <= searchSelection[0] - +(diff < 0)) searchSelection[0] -= diff;
				}
			}
			startSearch();
		});
		editor.on("selectionChange", (selection) => {
			if (isOpen && editor.focused) prevUserSelection = selection;
		});
		addListener(searchContainer, "click", (e) => {
			const target = e.target;
			const remove = editor.on("update", () => target.focus());
			elementHandlerMap.get(target)?.();
			if (target.matches(".pce-options>button")) {
				toggleAttr(target, "aria-pressed");
				startSearch(true);
			}
			remove();
		});
		addListener(findInput, "input", () => isOpen && startSearch(true));
		addListener(searchContainer, "keydown", (e) => {
			const shortcut = getModifierCode(e);
			const target = e.target;
			const keyCode = e.keyCode;
			const isFind = target == findInput;
			if (shortcut == (isMac ? 5 : 1)) {
				if (keyCodeButtonMap[keyCode]) {
					preventDefault(e);
					keyCodeButtonMap[keyCode].click();
				}
			} else if (keyCode == 13 && target.tagName == "INPUT") {
				preventDefault(e);
				if (!shortcut) isFind ? move(true) : replaceEl.click();
				else if (shortcut == 8 && isFind) move();
				else if (shortcut == (isMac ? 4 : 3) && !isFind) replaceAllEl.click();
				target.focus();
			} else if (!shortcut && keyCode == 27) close();
		});
		self.open = (focusInput) => {
			open(focusInput);
			startSearch();
		};
		replaceAPI.container.className = "pce-matches";
	};
	const searchContainer = template();
	const search = self.element = searchContainer.firstChild;
	const [toggle, div] = search.children;
	const rows = div.children;
	const [findContainer, closeEl] = rows[0].children;
	const [findInput, prevEl, nextEl, errorEl] = findContainer.children;
	const [replaceInput, replaceEl, replaceAllEl] = rows[1].children;
	const [matchCount, useRegExpEl, matchCaseEl, wholeWordEl, inSelectionEl] = rows[2].children;
	const [current, , total] = matchCount.childNodes;
	self.open = self.close = () => {};
	return self;
};
//#endregion
//#region src/extensions/search/invisibles.ts
/**
* Extension that highlights selected tabs and spaces as an overlay. To instead highlight
* all spaces and tabs, use {@link tokenizeInvisibles}.
*
* Requires styling from `prism-code-editor/invisibles.css`.
*/
var showInvisibles = () => {
	return (editor) => {
		const searchAPI = createSearchAPI(editor);
		const matches = searchAPI.matches;
		const container = searchAPI.container;
		const nodes = container.children;
		const tabs = [];
		const update = () => {
			const value = editor.value;
			const [start, end] = editor.getSelection();
			searchAPI.search(" |	", true, false, true, [start, end]);
			for (let i = 0, l = matches.length; i < l; i++) if (value[matches[i][0]] == "	" == !tabs[i]) nodes[i].className = (tabs[i] = !tabs[i]) ? "pce-tab" : "";
		};
		container.className = "pce-invisibles";
		if (editor.value) update();
		editor.on("selectionChange", update);
	};
};
//#endregion
export { highlightCurrentWord, highlightSelectionMatches, searchWidget, showInvisibles };

//# sourceMappingURL=index.js.map