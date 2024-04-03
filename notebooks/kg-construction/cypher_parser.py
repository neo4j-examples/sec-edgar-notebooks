import sys
import argparse
import re

from typing import List

def cypher_parser(cypher:str) -> List[str]:
    """
    Parse a Cypher module and return a list of statements
    """
    # Remove comments
    strip_single_comments = re.sub(r'//.*\n', '', cypher)
    strip_multi_comments = re.sub(r'/\*\*.*?\*/', '', strip_single_comments, flags=re.DOTALL)
    parsed = strip_multi_comments.split(';')
    parsed = [x.strip() for x in parsed]
    parsed = [x for x in parsed if x != '']

    return parsed

def parse_cypher_file(filename:str) -> List[str]:
    """
    Parse a Cypher file and return a list of statements
    """
    with open(filename, 'r') as f:
        cypher = f.read()
        return cypher_parser(cypher)

def main() -> int:
    """Parse cypher module and show some stats"""

    arg_parser = argparse.ArgumentParser(
                    prog='CypherModuleParser',
                    description='Parses a cypher module and shows some stats')
    arg_parser.add_argument('filename', nargs='+', help='Cypher module files to parse')
    args = arg_parser.parse_args()
    print(args.filename)
    
    for filename in args.filename:
          result = parse_cypher_file(filename)
          print(f"File: {filename}...")
          print(f"\tNumber of statements: {len(result)}")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())  # next section explains the use of sys.exit