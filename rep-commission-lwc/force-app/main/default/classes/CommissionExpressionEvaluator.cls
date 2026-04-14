/**
 * CommissionExpressionEvaluator
 * Evaluates arithmetic and conditional expressions stored in Calculation_Expression__c metadata.
 *
 * Supported syntax:
 *   {Field_API_Name__c}              — field value reference (case-insensitive)
 *   123 / 45.6                       — numeric literals
 *   +  -  *  /                       — arithmetic operators (standard precedence)
 *   ( )                              — parentheses for grouping
 *   IF(condition, trueVal, falseVal) — conditional; condition uses >, >=, <, <=, ==, !=
 *
 * Examples:
 *   {Brokered_Margin_Amount__c} * ({Brokered_Margin__c} / 100)
 *   IF({Team_Closing_Ratio__c} > 75, 3000, IF({Team_Closing_Ratio__c} >= 70, 1000, 0))
 *
 * Returns 0 on blank input or any parse error so a bad expression never breaks a trigger.
 */
public with sharing class CommissionExpressionEvaluator {

    private String               expr;
    private Integer              pos;
    private Map<String, Decimal> fieldValues;

    // ── Public entry point ────────────────────────────────────────────────────

    public static Decimal evaluate(String expression, Map<String, Decimal> fieldValues) {
        if (String.isBlank(expression)) return 0;
        CommissionExpressionEvaluator ev = new CommissionExpressionEvaluator();
        ev.expr        = expression.trim();
        ev.pos         = 0;
        ev.fieldValues = fieldValues;
        try {
            return ev.parseExpression();
        } catch (Exception e) {
            return 0; // never let a bad expression break the trigger
        }
    }

    // ── Parser (recursive descent) ────────────────────────────────────────────

    // Handles + and - (lowest precedence, left-to-right)
    private Decimal parseExpression() {
        Decimal left = parseTerm();
        while (pos < expr.length()) {
            skipWhitespace();
            if (pos >= expr.length()) break;
            String ch = expr.substring(pos, pos + 1);
            if (ch == '+') {
                pos++;
                left += parseTerm();
            } else if (ch == '-') {
                pos++;
                left -= parseTerm();
            } else {
                break;
            }
        }
        return left;
    }

    // Handles * and / (higher precedence, left-to-right)
    private Decimal parseTerm() {
        Decimal left = parseFactor();
        while (pos < expr.length()) {
            skipWhitespace();
            if (pos >= expr.length()) break;
            String ch = expr.substring(pos, pos + 1);
            if (ch == '*') {
                pos++;
                left *= parseFactor();
            } else if (ch == '/') {
                pos++;
                Decimal divisor = parseFactor();
                left = (divisor != 0) ? (left / divisor) : 0;
            } else {
                break;
            }
        }
        return left;
    }

    // Handles atomic values: IF function, field references, numeric literals,
    // parenthesised sub-expressions, unary minus
    private Decimal parseFactor() {
        skipWhitespace();
        if (pos >= expr.length()) return 0;

        String ch = expr.substring(pos, pos + 1);

        // Named function (currently only IF is supported)
        if (isLetter(ch)) {
            Integer start = pos;
            while (pos < expr.length() && isLetterOrDigit(expr.substring(pos, pos + 1))) pos++;
            String funcName = expr.substring(start, pos).toUpperCase();
            skipWhitespace();
            if (funcName == 'IF' && pos < expr.length() && expr.substring(pos, pos + 1) == '(') {
                pos++; // consume '('
                return parseIfFunction();
            }
            return 0; // unknown function
        }

        // Parenthesised expression
        if (ch == '(') {
            pos++;
            Decimal val = parseExpression();
            skipWhitespace();
            if (pos < expr.length() && expr.substring(pos, pos + 1) == ')') pos++;
            return val;
        }

        // Field reference: {Field_API_Name__c}
        if (ch == '{') {
            pos++;
            Integer start = pos;
            while (pos < expr.length() && expr.substring(pos, pos + 1) != '}') pos++;
            String fieldName = expr.substring(start, pos).trim().toLowerCase();
            if (pos < expr.length()) pos++; // consume '}'
            Decimal val = fieldValues.containsKey(fieldName) ? fieldValues.get(fieldName) : 0;
            return val != null ? val : 0;
        }

        // Unary minus
        if (ch == '-') {
            pos++;
            return -parseFactor();
        }

        // Numeric literal (integer or decimal)
        Integer start = pos;
        while (pos < expr.length() && isDigitOrDot(expr.substring(pos, pos + 1))) pos++;
        if (pos > start) {
            return Decimal.valueOf(expr.substring(start, pos));
        }

        pos++; // skip unrecognised character
        return 0;
    }

    // Parses IF(leftExpr comparator rightExpr, trueExpr, falseExpr)
    // Called after the opening '(' has been consumed.
    private Decimal parseIfFunction() {
        // Left side of condition
        Decimal left = parseExpression();
        skipWhitespace();

        // Comparison operator
        String op = readComparator();
        skipWhitespace();

        // Right side of condition
        Decimal right = parseExpression();
        skipWhitespace();

        // Comma before true branch
        if (pos < expr.length() && expr.substring(pos, pos + 1) == ',') pos++;
        Decimal trueVal = parseExpression();
        skipWhitespace();

        // Comma before false branch
        if (pos < expr.length() && expr.substring(pos, pos + 1) == ',') pos++;
        Decimal falseVal = parseExpression();
        skipWhitespace();

        // Closing ')'
        if (pos < expr.length() && expr.substring(pos, pos + 1) == ')') pos++;

        return applyComparator(left, op, right) ? trueVal : falseVal;
    }

    // Reads a comparator token: >=, <=, !=, >, <, ==
    private String readComparator() {
        skipWhitespace();
        if (pos >= expr.length()) return '';
        String c1 = expr.substring(pos, pos + 1);
        if (c1 != '>' && c1 != '<' && c1 != '=' && c1 != '!') return '';
        pos++;
        if (pos < expr.length() && expr.substring(pos, pos + 1) == '=') {
            pos++;
            return c1 + '=';
        }
        return c1;
    }

    private static Boolean applyComparator(Decimal left, String op, Decimal right) {
        if (op == '>')  return left > right;
        if (op == '>=') return left >= right;
        if (op == '<')  return left < right;
        if (op == '<=') return left <= right;
        if (op == '==') return left == right;
        if (op == '!=') return left != right;
        return false;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private void skipWhitespace() {
        while (pos < expr.length() && expr.substring(pos, pos + 1) == ' ') pos++;
    }

    private static Boolean isDigitOrDot(String c) {
        return c == '.' || '0123456789'.contains(c);
    }

    private static Boolean isLetter(String c) {
        return 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_'.contains(c);
    }

    private static Boolean isLetterOrDigit(String c) {
        return isLetter(c) || '0123456789'.contains(c);
    }
}
