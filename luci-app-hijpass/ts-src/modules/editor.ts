import baseclass from 'baseclass';
import { json } from '@codemirror/lang-json';
import { StreamLanguage } from '@codemirror/language';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { CodeEditorUtils } from '../utils/base/luci/editor';
import { firewallTemplateLanguage } from '../utils/feature/firewall/syntax';

const languages = { json: json(), shell: StreamLanguage.define(shell), firewall: firewallTemplateLanguage };

// LuCI 缓存模块实例，各页面复用同一份 CodeMirror 与语言包。
export default baseclass.extend({
    mount(widget: HTMLElement, language: keyof typeof languages, label: string) {
        CodeEditorUtils.mount(widget, languages[language], label);
    },
    configure(option: LuCI.form.TextValue, language: keyof typeof languages, label: string) {
        CodeEditorUtils.configure(option, languages[language], label);
    },
});
