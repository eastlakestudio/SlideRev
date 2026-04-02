import sys

def check_braces(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    stack = []
    for i, line in enumerate(lines):
        line_num = i + 1
        for char in line:
            if char == '{':
                stack.append(line_num)
            elif char == '}':
                if not stack:
                    print(f"ERROR: Extra '}}' at line {line_num}")
                else:
                    stack.pop()
    
    if stack:
        print(f"ERROR: Unclosed '{{' starting at lines: {stack}")
    else:
        print("Braces are balanced (globally).")

check_braces('RefinementView.swift')
