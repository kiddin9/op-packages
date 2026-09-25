import { t as testBracket } from "../../bracket-CStGDfC7.js";
//#region src/extensions/matchBrackets/index.ts
/**
* Extension that matches punctuation tokens together. Intended for matching brackets.
*
* Without rainbow brackets, this extension can be added dynamically with no downsides.
*
* @param rainbowBrackets Whether to add extra classes to brackets for styling. Defaults
* to `true`. When enabled, adding the extension dynamically will force a rerender to add
* these extra classes.
* @param pairs Which characters to match together. The opening character must be followed
* by the corresponding closing character. Defaults to `"()[]{}"`.
*/
var matchBrackets = (rainbowBrackets = true, pairs = "()[]{}") => {
	let bracketIndex;
	let sp;
	const stack = [];
	const self = (editor) => {
		editor.extensions.matchBrackets = self;
		editor.on("tokenize", matchBrackets);
		if (rainbowBrackets && editor.tokens[0]) editor.update();
		else matchBrackets(editor.tokens);
	};
	const brackets = self.brackets = [];
	const pairMap = self.pairs = [];
	const matchBrackets = (tokens) => {
		pairMap.length = brackets.length = sp = bracketIndex = 0;
		matchRecursive(tokens, 0);
		if (rainbowBrackets) for (let i = 0, bracket; bracket = brackets[i];) {
			let alias = bracket[0].alias;
			bracket[0].alias = (alias ? alias + " " : "") + `bracket-${i++ in pairMap ? "level-" + bracket[3] % 12 : "error"}`;
		}
	};
	const matchRecursive = (tokens, position) => {
		let token;
		let i = 0;
		for (; token = tokens[i++];) {
			let length = token.length;
			if (typeof token != "string") {
				let content = token.content;
				if (Array.isArray(content)) matchRecursive(content, position);
				else if ((token.alias || token.type) == "punctuation") {
					let bracketType = testBracket(content, pairs, length - 1);
					let isOpening = bracketType % 2;
					if (bracketType) {
						brackets[bracketIndex] = [
							token,
							position,
							position + length,
							sp,
							content,
							!!isOpening
						];
						if (isOpening) stack[sp++] = [bracketIndex, bracketType + 1];
						else for (let i = sp, entry; entry = stack[--i];) if (bracketType == entry[1]) {
							pairMap[pairMap[bracketIndex] = entry[0]] = bracketIndex;
							brackets[bracketIndex][3] = sp = i;
							break;
						}
						bracketIndex++;
					}
				}
			}
			position += length;
		}
	};
	return self;
};
//#endregion
export { matchBrackets };

//# sourceMappingURL=index.js.map