pragma Singleton

import QtQuick

QtObject {
    function normalized(text) {
        return String(text).replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/,/g, ".");
    }

    // Arithmetic-only recursive-descent parser. Unlike eval(), expressions
    // cannot access QML objects or the host environment.
    function calculate(text) {
        const source = normalized(text).replace(/\s+/g, "");
        var index = 0;
        function number() {
            const match = source.slice(index).match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i);
            if (!match) throw new Error("number expected");
            index += match[0].length;
            return Number(match[0]);
        }
        function primary() {
            var value;
            if (source[index] === "(") {
                index += 1;
                value = addSubtract();
                if (source[index] !== ")") throw new Error("missing parenthesis");
                index += 1;
            } else if (source[index] === "+" || source[index] === "-") {
                const sign = source[index++];
                value = primary();
                if (sign === "-") value = -value;
            } else {
                value = number();
            }
            while (source[index] === "%") {
                value /= 100;
                index += 1;
            }
            return value;
        }
        function multiplyDivide() {
            var value = primary();
            while (source[index] === "*" || source[index] === "/") {
                const op = source[index++];
                const right = primary();
                value = op === "*" ? value * right : value / right;
            }
            return value;
        }
        function addSubtract() {
            var value = multiplyDivide();
            while (source[index] === "+" || source[index] === "-") {
                const op = source[index++];
                const right = multiplyDivide();
                value = op === "+" ? value + right : value - right;
            }
            return value;
        }
        if (source === "") throw new Error("empty expression");
        const value = addSubtract();
        if (index !== source.length || !Number.isFinite(value)) throw new Error("invalid expression");
        return value;
    }

    function formatted(value) {
        if (Object.is(value, -0)) return "0";
        return Number(value.toPrecision(12)).toString();
    }

    function evaluate(expression) {
        return formatted(calculate(expression));
    }
}
