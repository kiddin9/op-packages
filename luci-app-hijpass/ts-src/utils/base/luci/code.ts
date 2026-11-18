// 按 LuCI 当前文字颜色选择代码配色，兼容主题手动切换的明暗模式。
export function codeColors() {
    const color = getComputedStyle(document.body).color.match(/\d+/g)?.slice(0, 3).map(Number) || [0, 0, 0];
    const dark = color.reduce((sum, value) => sum + value, 0) > 384;
    const palette = dark
        ? { keyword: '#8cc8ff', string: '#a5d6a7', number: '#d2a8ff', comment: '#a2adb9', variable: '#ffb86c' }
        : { keyword: '#005cc5', string: '#116329', number: '#8250df', comment: '#57606a', variable: '#953800' };
    return { dark, palette };
}
