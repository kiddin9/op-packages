import ui from 'ui';
import { parser } from '@lezer/json';
import { highlightTree, tagHighlighter, tags } from '@lezer/highlight';
import { codeColors } from '../../base/luci/code';

const highlighter = tagHighlighter([
    { tag: tags.propertyName, class: 'variable' },
    { tag: tags.string, class: 'string' },
    { tag: tags.number, class: 'number' },
    { tag: [tags.bool, tags.null], class: 'keyword' },
]);

// 预览保持原生只读文本；只给语法节点着色，不改写 JSON 内容和缩进。
function render(source: string, label: string): HTMLElement {
    const content = E('pre', {
        class: 'hijpass-config-preview', tabindex: '0', role: 'region', 'aria-label': label,
        style: 'max-height:500px;max-width:100%;overflow:auto;padding:10px;border-radius:4px;white-space:pre;font-size:.85rem;tab-size:2',
    }) as HTMLElement;
    const { palette } = codeColors();
    let position = 0;
    highlightTree(parser.parse(source), highlighter, (from, to, style) => {
        content.appendChild(document.createTextNode(source.slice(position, from)));
        // 配置值可能包含 HTML；始终创建文本节点，避免把用户内容解释为标记。
        content.appendChild(E('span', { style: `color:${palette[style]}` },
            document.createTextNode(source.slice(from, to))));
        position = to;
    });
    content.appendChild(document.createTextNode(source.slice(position)));
    return content;
}

function show(title: string, source: string) {
    ui.showModal(title, [
        E('div', { class: 'cbi-section' }, [render(source, _('Config Preview'))]),
        E('div', { class: 'right' }, [
            E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close')),
        ]),
    ]);
}

export const ConfigPreviewUtils = { render, show };
