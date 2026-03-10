// AdvancedMath.js - Lightweight math library for Noctalia Calculator
// Provides advanced mathematical functions beyond basic arithmetic

// Helper function to convert degrees to radians
function toRadians(degrees) {
    return degrees * (Math.PI / 180);
}

// Helper function to convert radians to degrees
function toDegrees(radians) {
    return radians * (180 / Math.PI);
}

// Constants
var constants = {
    PI: Math.PI,
    E: Math.E,
    LN2: Math.LN2,
    LN10: Math.LN10,
    LOG2E: Math.LOG2E,
    LOG10E: Math.LOG10E,
    SQRT1_2: Math.SQRT1_2,
    SQRT2: Math.SQRT2
};

// Safe evaluation function that handles advanced math
function evaluate(expression) {
    try {
        // Replace mathematical constants
        var processed = expression
            .replace(/\bpi\b/gi, Math.PI)
            .replace(/\be\b/gi, Math.E);

        // Replace function calls with Math object equivalents
        processed = processed
            // Trigonometric functions
            .replace(/\bsin\s*\(/g, 'Math.sin(')
            .replace(/\bcos\s*\(/g, 'Math.cos(')
            .replace(/\btan\s*\(/g, 'Math.tan(')
            .replace(/\basin\s*\(/g, 'Math.asin(')
            .replace(/\bacos\s*\(/g, 'Math.acos(')
            .replace(/\batan\s*\(/g, 'Math.atan(')
            .replace(/\batan2\s*\(/g, 'Math.atan2(')
            
            // Hyperbolic functions
            .replace(/\bsinh\s*\(/g, 'Math.sinh(')
            .replace(/\bcosh\s*\(/g, 'Math.cosh(')
            .replace(/\btanh\s*\(/g, 'Math.tanh(')
            .replace(/\basinh\s*\(/g, 'Math.asinh(')
            .replace(/\bacosh\s*\(/g, 'Math.acosh(')
            .replace(/\batanh\s*\(/g, 'Math.atanh(')
            
            // Logarithmic and exponential functions
            .replace(/\blog\s*\(/g, 'Math.log10(')
            .replace(/\bln\s*\(/g, 'Math.log(')
            .replace(/\bexp\s*\(/g, 'Math.exp(')
            .replace(/\bpow\s*\(/g, 'Math.pow(')
            
            // Root functions
            .replace(/\bsqrt\s*\(/g, 'Math.sqrt(')
            .replace(/\bcbrt\s*\(/g, 'Math.cbrt(')
            
            // Rounding and absolute
            .replace(/\babs\s*\(/g, 'Math.abs(')
            .replace(/\bfloor\s*\(/g, 'Math.floor(')
            .replace(/\bceil\s*\(/g, 'Math.ceil(')
            .replace(/\bround\s*\(/g, 'Math.round(')
            .replace(/\btrunc\s*\(/g, 'Math.trunc(')
            
            // Min/Max
            .replace(/\bmin\s*\(/g, 'Math.min(')
            .replace(/\bmax\s*\(/g, 'Math.max(')
            
            // Random
            .replace(/\brandom\s*\(\s*\)/g, 'Math.random()');

        // Handle degree versions of trig functions
        processed = processed
            .replace(/\bsind\s*\(/g, '(function(x) { return Math.sin(' + (Math.PI / 180) + ' * x); })(')
            .replace(/\bcosd\s*\(/g, '(function(x) { return Math.cos(' + (Math.PI / 180) + ' * x); })(')
            .replace(/\btand\s*\(/g, '(function(x) { return Math.tan(' + (Math.PI / 180) + ' * x); })(');

        // Handle ^ for exponentiation: convert 2^3 to Math.pow(2,3)
        processed = processed.replace(/([\d.]+|\))\^([\d.]+|\([^)]*\))/g, 'Math.pow($1,$2)');

        // Sanitize expression (only allow safe characters)
        if (!/^[0-9+\-*/().\s\w,]+$/.test(processed)) {
            throw new Error("Invalid characters in expression");
        }

        // Evaluate the processed expression
        var result = eval(processed);
        
        if (!isFinite(result) || isNaN(result)) {
            throw new Error("Invalid result");
        }

        return result;
    } catch (error) {
        throw new Error("Evaluation failed: " + error.message);
    }
}

// Format result for display
function formatResult(result) {
    if (Number.isInteger(result)) {
        return result.toString();
    }
    
    // Handle very large or very small numbers
    if (Math.abs(result) >= 1e15 || (Math.abs(result) < 1e-6 && result !== 0)) {
        return result.toExponential(6);
    }
    
    // Normal decimal formatting
    return parseFloat(result.toFixed(10)).toString();
}

// Get list of available functions for help
function getAvailableFunctions() {
    return [
        // Basic arithmetic: +, -, *, /, %, ^, ()
        
        // Trigonometric functions
        "sin(x), cos(x), tan(x) - trigonometric functions (radians)",
        "sind(x), cosd(x), tand(x) - trigonometric functions (degrees)",
        "asin(x), acos(x), atan(x) - inverse trigonometric",
        "atan2(y, x) - two-argument arctangent",
        
        // Hyperbolic functions
        "sinh(x), cosh(x), tanh(x) - hyperbolic functions",
        "asinh(x), acosh(x), atanh(x) - inverse hyperbolic",
        
        // Logarithmic and exponential
        "log(x) - base 10 logarithm",
        "ln(x) - natural logarithm",
        "exp(x) - e^x",
        "pow(x, y) - x^y",
        
        // Root functions
        "sqrt(x) - square root",
        "cbrt(x) - cube root",
        
        // Rounding and absolute
        "abs(x) - absolute value",
        "floor(x), ceil(x), round(x), trunc(x)",
        
        // Min/Max/Random
        "min(a, b, ...), max(a, b, ...)",
        "random() - random number 0-1",
        
        // Constants
        "pi, e - mathematical constants"
    ];
}
