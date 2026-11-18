import { EditorState, type Extension } from '@codemirror/state';
import { EditorView, keymap, lineNumbers, highlightActiveLine, drawSelection } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { HighlightStyle, syntaxHighlighting, bracketMatching } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import { codeColors } from './code';

function mount(widget: HTMLElement, language: Extension, label: string) {
    const textarea = widget.querySelector('textarea') as HTMLTextAreaElement;
    const native = L.dom.findClassInstance(widget) as LuCI.ui.AbstractElement;
    const { dark, palette } = codeColors();
    const theme = EditorView.theme({
        '&': { width: '100%', minWidth: '0', boxSizing: 'border-box', height: '38rem', minHeight: '18rem', maxWidth: '100%', color: 'inherit', backgroundColor: 'transparent',
            border: '1px solid var(--border-color, #7778)', borderRadius: '3px', resize: 'vertical', overflow: 'hidden' },
        '&.cm-focused': { outline: '2px solid currentColor', outlineOffset: '-1px' },
        '.cm-scroller': { overflow: 'auto', fontFamily: 'ui-monospace, SFMono-Regular, Consolas, monospace', fontSize: '.9rem' },
        '.cm-content': { padding: '.5rem 0', caretColor: 'currentColor' },
        '.cm-gutters': { color: 'inherit', borderRight: '1px solid #7774' },
        '.cm-lineNumbers .cm-gutterElement': { opacity: '.65' },
        '.cm-activeLine': { backgroundColor: dark ? '#ffffff08' : '#00000005' },
    }, { dark });
    const highlights = HighlightStyle.define([
        { tag: [tags.keyword, tags.meta, tags.bool, tags.null], color: palette.keyword },
        { tag: tags.string, color: palette.string },
        { tag: [tags.number, tags.atom], color: palette.number },
        { tag: tags.comment, color: palette.comment },
        { tag: [tags.variableName, tags.propertyName], color: palette.variable },
    ]);
    const view = new EditorView({
        parent: widget,
        state: EditorState.create({ doc: textarea.value, extensions: [
            lineNumbers(), history(), drawSelection(), highlightActiveLine(), bracketMatching(),
            keymap.of([...defaultKeymap, ...historyKeymap]),
            language, syntaxHighlighting(highlights), theme,
            EditorState.readOnly.of(textarea.readOnly || textarea.disabled),
            EditorView.editable.of(!textarea.readOnly && !textarea.disabled),
            EditorView.contentAttributes.of({ 'aria-label': label, spellcheck: 'false', autocorrect: 'off', autocapitalize: 'off' }),
            EditorView.updateListener.of(update => {
                if (!update.docChanged) return;
                // 保留原生 LuCI textarea 与事件，保存、校验仍使用既有表单逻辑。
                textarea.value = update.state.doc.toString();
                textarea.dispatchEvent(new Event('change', { bubbles: true }));
            }),
        ] }),
    });
    textarea.hidden = true;
    textarea.style.display = 'none';
    const setValue = native.setValue.bind(native);
    native.setValue = value => {
        const text = value == null ? '' : String(value);
        setValue(text);
        if (view.state.doc.toString() !== text)
            view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: 0 }, scrollIntoView: true });
    };
    // LuCI 保存后会重新渲染表单；移除旧节点时释放编辑器的观察器与事件。
    let attached = widget.isConnected;
    const observer = new MutationObserver(() => {
        if (widget.isConnected) { attached = true; return; }
        if (!attached) return;
        view.destroy();
        observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
}


// 在原生 textarea 渲染后挂载；读写接口仍属于 LuCI 表单，不接管文件保存。
function configure(option: LuCI.form.TextValue, language: Extension, label: string) {
    const renderWidget = option.renderWidget;
    option.renderWidget = function (...args: any[]) {
        const widget = renderWidget.apply(this, args) as HTMLElement;
        mount(widget, language, label);
        return widget;
    };
}

export const CodeEditorUtils = { mount, configure };
