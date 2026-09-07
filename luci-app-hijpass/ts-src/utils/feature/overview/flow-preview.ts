import { buildConfigurationFlowPreview, type FlowBranch, type FlowDiagram, type FlowStep, type FlowPage } from "./flow-model";

const FLOW_STYLE = `
    a.hijpass-flow-step,
    a.hijpass-flow-branch__condition {
        display: block;
        color: inherit;
        text-decoration: none;
    }

    a.hijpass-flow-step:hover,
    a.hijpass-flow-branch__condition:hover {
        border-color: var(--primary-color, #4b6cb7);
    }

    a.hijpass-flow-step:focus-visible,
    a.hijpass-flow-branch__condition:focus-visible {
        outline: 2px solid var(--primary-color, #4b6cb7);
        outline-offset: 2px;
    }

    .hijpass-flow-card h3 {
        margin: 0;
    }

    .hijpass-flow-step[data-tone="warning"] {
        color: var(--warning-color, #b26a00);
    }

    .hijpass-flow-list {
        display: grid;
        gap: 1rem;
    }

    .hijpass-flow-card {
        --hijpass-flow-node-width: 14rem;
        --hijpass-flow-condition-width: 13rem;
        box-sizing: border-box;
        min-width: 0;
        padding: 1rem;
    }

    .hijpass-flow-scroll {
        max-width: 100%;
        margin-top: .75rem;
        padding: 0 0 .5rem;
        overflow-x: auto;
        overflow-y: hidden;
        overscroll-behavior-inline: contain;
        scrollbar-gutter: stable;
    }

    .hijpass-flow-scroll:focus-visible {
        outline: 2px solid var(--primary-color, #4b6cb7);
        outline-offset: 2px;
    }

    .hijpass-flow-tree {
        display: flex;
        align-items: center;
        width: max-content;
        min-width: max-content;
    }

    .hijpass-flow-chain {
        display: flex;
        flex-wrap: nowrap;
        align-items: center;
        gap: .5rem;
        width: max-content;
        min-width: max-content;
        margin: 0;
        padding: 0;
        list-style: none;
    }

    .hijpass-flow-chain > li:not(.hijpass-flow-arrow) {
        display: flex;
        flex: 0 0 var(--hijpass-flow-node-width);
        width: var(--hijpass-flow-node-width);
    }

    .hijpass-flow-step {
        box-sizing: border-box;
        width: 100%;
        min-width: 0;
        padding: .75rem;
        border: 1px solid rgba(127, 127, 127, .45);
        border-left-width: 4px;
        border-radius: 4px;
        overflow-wrap: anywhere;
    }

    .hijpass-flow-step[data-tone="proxy"] {
        border-left-color: var(--primary-color, #4b6cb7);
    }

    .hijpass-flow-step[data-tone="direct"] {
        border-left-color: var(--success-color, #2e7d32);
    }

    .hijpass-flow-step[data-tone="muted"] {
        opacity: .7;
    }

    .hijpass-flow-step[data-tone="warning"] {
        border-left-color: currentColor;
    }

    .hijpass-flow-step__detail,
    .hijpass-flow-branch__detail {
        display: block;
        margin-top: .25rem;
        color: var(--text-color-medium, #777);
        font-size: .8125rem;
        line-height: 1.4;
    }

    .hijpass-flow-step__detail {
        white-space: pre-line;
    }

    .hijpass-flow-arrow {
        display: flex;
        flex: 0 0 auto;
        align-items: center;
        justify-content: center;
        color: var(--text-color-medium, #777);
        font-size: 1.25rem;
    }

    .hijpass-flow-branches {
        position: relative;
        display: grid;
        gap: .75rem;
        margin: 0;
        padding: 0;
        list-style: none;
    }

    .hijpass-flow-branches--parallel {
        margin-left: 1.5rem;
    }

    .hijpass-flow-branches--parallel::before {
        position: absolute;
        top: 50%;
        right: 100%;
        width: 1.5rem;
        border-top: 2px solid rgba(127, 127, 127, .6);
        content: '';
    }

    .hijpass-flow-branch {
        display: grid;
        align-items: stretch;
        gap: .5rem;
        min-height: 4.25rem;
    }

    .hijpass-flow-branch--parallel {
        grid-template-columns: 1.5rem var(--hijpass-flow-condition-width) 1.5rem auto;
    }

    .hijpass-flow-branch__joint {
        position: relative;
        display: flex;
        align-self: stretch;
        align-items: center;
        justify-content: flex-end;
        color: var(--text-color-medium, #777);
        font-size: 1.25rem;
        line-height: 1;
    }

    .hijpass-flow-branch__joint::after {
        position: absolute;
        top: -.375rem;
        bottom: -.375rem;
        left: 0;
        border-left: 2px solid rgba(127, 127, 127, .6);
        content: '';
    }

    .hijpass-flow-branch--parallel:first-child .hijpass-flow-branch__joint::after {
        top: 50%;
    }

    .hijpass-flow-branch--parallel:last-child .hijpass-flow-branch__joint::after {
        bottom: 50%;
    }

    .hijpass-flow-branch--parallel:only-child .hijpass-flow-branch__joint::after {
        display: none;
    }

    .hijpass-flow-branch__condition {
        box-sizing: border-box;
        width: var(--hijpass-flow-condition-width);
        padding: .75rem;
        border: 1px dashed rgba(127, 127, 127, .55);
        border-radius: 4px;
        overflow-wrap: anywhere;
    }

    .hijpass-flow-branch .hijpass-flow-chain {
        margin: 0;
    }

    .hijpass-flow-ordered {
        display: grid;
        grid-template-columns: auto auto auto;
        grid-template-rows: auto auto auto;
        column-gap: .5rem;
        width: max-content;
        min-width: max-content;
        align-items: start;
    }

    .hijpass-flow-ordered__prefix {
        grid-column: 1;
        grid-row: 2;
        align-self: center;
    }

    .hijpass-flow-ordered__entry {
        grid-column: 2;
        grid-row: 2;
        align-self: center;
        width: auto;
    }

    .hijpass-flow-ordered__description {
        display: flex;
        grid-column: 3;
        grid-row: 1;
        align-items: center;
        height: 1.5rem;
        margin: 0 0 .25rem;
        color: var(--text-color-medium, #777);
        font-size: .8125rem;
        line-height: 1.25;
        white-space: nowrap;
    }

    .hijpass-flow-ordered__first,
    .hijpass-flow-ordered__rest {
        grid-column: 3;
    }

    .hijpass-flow-ordered__first {
        grid-row: 2;
        align-self: stretch;
    }

    .hijpass-flow-ordered__rest {
        grid-row: 3;
    }

    .hijpass-flow-branches--ordered {
        gap: 0;
    }

    .hijpass-flow-branch--ordered {
        grid-template-columns: var(--hijpass-flow-condition-width) 1.5rem auto;
    }

    .hijpass-flow-branch--ordered .hijpass-flow-branch__condition,
    .hijpass-flow-branch--ordered .hijpass-flow-step {
        display: flex;
        min-height: 4.25rem;
        flex-direction: column;
        justify-content: center;
    }

    .hijpass-flow-branch--ordered .hijpass-flow-chain {
        align-items: stretch;
    }

    .hijpass-flow-order-arrow {
        display: flex;
        width: var(--hijpass-flow-condition-width);
        height: 1.25rem;
        align-items: center;
        justify-content: center;
        color: var(--text-color-medium, #777);
        font-size: 1rem;
        line-height: 1;
    }

    @media (max-width: 900px) {
        .hijpass-flow-card {
            --hijpass-flow-node-width: 13rem;
            --hijpass-flow-condition-width: 12rem;
        }
    }

`;

function ensureFlowPreviewStyles() {
    if (document.getElementById('hijpass-flow-preview-styles')) return;
    const style = document.createElement('style');
    style.id = 'hijpass-flow-preview-styles';
    style.textContent = FLOW_STYLE;
    document.head.appendChild(style);
}

function pageUrl(page: FlowPage): string {
    return L.url(page === 'dhcp' ? 'admin/network/dhcp' : 'admin/services/hijpass/' + page);
}

function renderStep(step: FlowStep) {
    return E(step.page ? 'a' : 'div', {
        ...(step.page ? { href: pageUrl(step.page) } : {}),
        'class': 'hijpass-flow-step',
        'data-tone': step.tone || 'normal',
    }, [
        E('strong', {}, step.title),
        step.detail ? E('span', { 'class': 'hijpass-flow-step__detail' }, step.detail) : '',
    ]);
}

function renderChain(steps: FlowStep[]) {
    const children: HTMLElement[] = [];
    steps.forEach((step, index) => {
        children.push(E('li', {}, [renderStep(step)]) as HTMLElement);
        if (index < steps.length - 1) {
            children.push(E('li', { 'class': 'hijpass-flow-arrow', 'aria-hidden': 'true' }, '→') as HTMLElement);
        }
    });
    return E('ol', { 'class': 'hijpass-flow-chain' }, children);
}

function renderParallelBranch(branch: FlowBranch) {
    return E('li', { 'class': 'hijpass-flow-branch hijpass-flow-branch--parallel' }, [
        E('span', { 'class': 'hijpass-flow-branch__joint', 'aria-hidden': 'true' }, '→'),
        E(branch.page ? 'a' : 'div', { 'class': 'hijpass-flow-branch__condition', ...(branch.page ? { href: pageUrl(branch.page) } : {}) }, [
            E('strong', {}, branch.condition),
            branch.detail ? E('span', { 'class': 'hijpass-flow-branch__detail' }, branch.detail) : '',
        ]),
        E('span', { 'class': 'hijpass-flow-arrow', 'aria-hidden': 'true' }, '→'),
        renderChain(branch.steps),
    ]);
}

function renderOrderedBranch(branch: FlowBranch) {
    return E('li', { 'class': 'hijpass-flow-branch hijpass-flow-branch--ordered' }, [
        E(branch.page ? 'a' : 'div', { 'class': 'hijpass-flow-branch__condition', ...(branch.page ? { href: pageUrl(branch.page) } : {}) }, [
            E('strong', {}, branch.condition),
            branch.detail ? E('span', { 'class': 'hijpass-flow-branch__detail' }, branch.detail) : '',
        ]),
        E('span', { 'class': 'hijpass-flow-arrow', 'aria-hidden': 'true' }, '→'),
        renderChain(branch.steps),
    ]);
}

function renderOrderedTree(steps: FlowStep[], branches: FlowBranch[], description?: string) {
    const remaining: HTMLElement[] = [];
    branches.slice(1).forEach(branch => {
        remaining.push(E('li', {
            'class': 'hijpass-flow-order-arrow',
            'aria-hidden': 'true',
        }, '↓') as HTMLElement);
        remaining.push(renderOrderedBranch(branch) as HTMLElement);
    });

    return E('div', {
        'class': 'hijpass-flow-tree hijpass-flow-ordered',
        'data-branch-mode': 'ordered',
    }, [
        E('p', { 'class': 'hijpass-flow-ordered__description' }, description || ''),
        E('div', { 'class': 'hijpass-flow-ordered__prefix' }, renderChain(steps)),
        E('span', { 'class': 'hijpass-flow-arrow hijpass-flow-ordered__entry', 'aria-hidden': 'true' }, '→'),
        E('ol', {
            'class': 'hijpass-flow-branches hijpass-flow-branches--ordered hijpass-flow-ordered__first',
        }, [renderOrderedBranch(branches[0])]),
        remaining.length > 0 ? E('ol', {
            'class': 'hijpass-flow-branches hijpass-flow-branches--ordered hijpass-flow-ordered__rest',
        }, remaining) : '',
    ]);
}

function renderBranches(diagram: FlowDiagram) {
    if (!diagram.branches?.length) return '';
    return E('ul', {
        'class': 'hijpass-flow-branches hijpass-flow-branches--parallel',
    }, diagram.branches.map(renderParallelBranch));
}

function renderTree(diagram: FlowDiagram) {
    const tree = diagram.branchMode === 'ordered' && diagram.branches?.length
        ? renderOrderedTree(diagram.steps, diagram.branches, diagram.branchDescription)
        : E('div', {
            'class': 'hijpass-flow-tree',
            'data-branch-mode': diagram.branchMode || 'parallel',
        }, [
            renderChain(diagram.steps),
            renderBranches(diagram),
        ]);

    return E('div', {
        'class': 'hijpass-flow-scroll',
        'role': 'region',
        'aria-label': diagram.title,
        'tabindex': '0',
    }, [tree]);
}

const FlowPreviewUtils = {
    createConfigurationFlowPreview: function () {
        ensureFlowPreviewStyles();
        const preview = buildConfigurationFlowPreview();
        return E('div', { 'class': 'hijpass-flow-preview' }, [
            E('div', { 'class': 'cbi-section-descr' },
                _('Generated from saved settings. Branches show configured decisions, not a live packet trace.')),
            E('div', { 'class': 'hijpass-flow-list' }, preview.diagrams.map(diagram =>
                E('section', {
                    'class': 'hijpass-flow-card',
                    'aria-labelledby': 'hijpass-flow-' + diagram.id,
                }, [
                    E('h3', { 'id': 'hijpass-flow-' + diagram.id }, diagram.title),
                    renderTree(diagram),
                ])))
        ]);
    },
};

export { FlowPreviewUtils };
