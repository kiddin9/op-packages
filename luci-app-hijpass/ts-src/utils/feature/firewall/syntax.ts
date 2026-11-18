import { StreamLanguage, StringStream } from '@codemirror/language';

type State = {
    mode: 'nft' | 'statement' | 'expression' | 'comment';
    quote: string;
    nftQuote: string;
    blockComment: boolean;
};

const nftKeywords = new Set(('table chain set map type hook priority policy flags elements timeout gc-interval auto-merge '
    + 'accept drop reject return jump goto counter tproxy redirect masquerade snat dnat '
    + 'meta ct fib ip ip6 ether tcp udp th iif iifname oif oifname skgid l4proto mark state direction '
    + 'daddr saddr dport sport new related reply local to interval filter route nat inet ipv4_addr ipv6_addr').split(' '));
const ucodeKeywords = new Set(('let const if elif else endif for endfor while function return break continue '
    + 'try catch throw import export from in switch case default die').split(' '));

function comment(stream: StringStream, end: string) {
    const position = stream.string.indexOf(end, stream.pos);
    stream.pos = position < 0 ? stream.string.length : position + end.length;
    return position >= 0;
}

function string(stream: StringStream, quote: string, template: boolean) {
    while (!stream.eol()) {
        // nft 字符串也可包含模板表达式，先停在开标签处再切换语言。
        if (template && stream.match(/^\{[{%#]/, false)) return false;
        const ch = stream.next();
        if (ch === '\\') stream.next();
        else if (ch === quote) return true;
    }
    return false;
}

// 流式词法只负责着色；模板及 nft 的有效性仍由后端生成和 nft 校验判断。
export const firewallTemplateLanguage = StreamLanguage.define<State>({
    name: 'nftables-ucode',
    startState: () => ({ mode: 'nft', quote: '', nftQuote: '', blockComment: false }),
    copyState: state => ({ ...state }),
    token(stream, state) {
        if (state.mode === 'comment') {
            if (comment(stream, '#}')) state.mode = 'nft';
            return 'comment';
        }
        if (state.blockComment) {
            if (comment(stream, '*/')) state.blockComment = false;
            return 'comment';
        }
        if (state.quote) {
            if (string(stream, state.quote, false)) state.quote = '';
            return 'string';
        }
        if (state.mode === 'nft') {
            const open = stream.match(/^\{([{%#])/);
            if (open) {
                state.mode = open[1] === '#' ? 'comment' : open[1] === '%' ? 'statement' : 'expression';
                return state.mode === 'comment' ? 'comment' : 'meta';
            }
            if (state.nftQuote) {
                if (string(stream, state.nftQuote, true)) state.nftQuote = '';
                return 'string';
            }
        } else if (stream.match(state.mode === 'statement' ? /^-?%\}/ : /^-?\}\}/)) {
            state.mode = 'nft';
            return 'meta';
        }
        if (stream.eatSpace()) return null;
        if (state.mode !== 'nft' && stream.match('/*')) {
            state.blockComment = !comment(stream, '*/');
            return 'comment';
        }
        if (stream.match(state.mode === 'nft' ? /^#/ : /^\/\//)) {
            stream.skipToEnd();
            return 'comment';
        }
        if (stream.match(/^["']/)) {
            const quote = stream.current();
            if (!string(stream, quote, state.mode === 'nft')) {
                if (state.mode === 'nft') state.nftQuote = quote;
                else state.quote = quote;
            }
            return 'string';
        }
        if (stream.match(/^(?:0x[\da-f]+|\d+(?:\.\d+)*(?:\/\d+)?)/i)) return 'number';
        if (stream.match(/^[@$][\w-]+/)) return 'variableName';
        const word = stream.match(state.mode === 'nft' ? /^[a-zA-Z_][\w-]*/ : /^[a-zA-Z_]\w*/);
        if (word) {
            if (/^(true|false|null)$/.test(word[0])) return 'atom';
            return (state.mode === 'nft' ? nftKeywords : ucodeKeywords).has(word[0]) ? 'keyword' : 'variableName';
        }
        if (stream.match(/^[{}()[\]]/)) return 'bracket';
        if (stream.match(/^[!=<>+*\/%&|?:-]+/)) return 'operator';
        stream.next();
        return null;
    },
});
