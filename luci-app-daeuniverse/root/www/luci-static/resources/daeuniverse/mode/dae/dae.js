(function(mod) {
  if (typeof exports == "object" && typeof module == "object")
    mod(require("../../lib/codemirror"));
  else if (typeof define == "function" && define.amd)
    define(["../../lib/codemirror"], mod);
  else
    mod(CodeMirror);
})(function(CodeMirror) {
"use strict";

CodeMirror.defineMode("dae", function(config) {
  var indentUnit = config.indentUnit;

  function tokenBase(stream, state) {
    if (stream.eatSpace()) return null;

    if (stream.match("#")) {
      stream.skipToEnd();
      return "comment";
    }

    var wordPattern = /^([a-zA-Z_][a-zA-Z_0-9\/\^*.+\-=@$!#%]*|[\/\^*.+\-0-9][a-zA-Z_0-9\/\^*.+\-=@$!#%]*)/;

    if (state.expectOutbound) {
      if (stream.match(wordPattern)) {
        state.expectOutbound = false;
        return "keyword";
      }
    }

    if (stream.match("->")) return "operator marker";
    if (stream.match("&&") || stream.match("!")) return "operator";
    if (stream.match(":")) return "operator";

    if (stream.match(/^"([^"\\]|\\.)*"/) || stream.match(/^'([^'\\]|\\.)*'/)) return "string";

    if (stream.match(/^([0-9]+(\.[0-9]+)+(?:\/[0-9]+)?|[a-fA-F0-9:]*::[a-fA-F0-9:]*(?:\/[0-9]+)?|[a-fA-F0-9]+(:[a-fA-F0-9]+){2,}(?:\/[0-9]+)?|[0-9]+(\.[0-9]+)?(%|[a-zA-Z]+)?)/)) return "number";

    if (stream.match(new RegExp(wordPattern.source.slice(1) + "\\s*(?={)"))) {
      return "keyword";
    }

    if (stream.match(/^(geosite|geoip|pname|domain|dip|sip|dport|sport|l4proto|ipversion_prefer|fixed_domain_ttl|subtag|name|qtype|qname|upstream|ip|mac|fallback)(?=\s*:)/)) {
      return "variable-2";
    }

    if (stream.match(new RegExp(wordPattern.source.slice(1) + "(?=\\s*:)"))) {
      return "variable-3";
    }

    if (stream.match(new RegExp("(!)?\\s*" + wordPattern.source.slice(1) + "\\s*(?=\\()"))) {
      return "def";
    }

    if (stream.match(/^(block|direct|accept|reject)\b/)) {
      return "keyword";
    }

    if (stream.match(/^[{}()\[\]]/)) return "bracket";

    if (stream.match(wordPattern)) {
      return "variable";
    }

    stream.next();
    return null;
  }

  return {
    startState: function() {
      return { tokenize: tokenBase, stack: [], expectOutbound: false };
    },
    token: function(stream, state) {
      var style = state.tokenize(stream, state);
      var cur = stream.current();
      if (style === "operator marker") {
        state.expectOutbound = true;
      } else if (style === "variable-3" && cur === "fallback") {
        state.expectOutbound = true;
      } else if (style !== null && style !== "comment" && !/^\s*:?\s*$/.test(cur)) {
        state.expectOutbound = false;
      }
      if (cur == "{") state.stack.push("{");
      else if (cur == "}") state.stack.pop();
      return style;
    },
    indent: function(state, textAfter) {
      var n = state.stack.length;
      if (/^\}/.test(textAfter)) n--;
      return n * indentUnit;
    },
    lineComment: "#",
    fold: "brace"
  };
});

CodeMirror.defineMIME("text/x-dae", "dae");
});
