"""SuperLite OS — Entry point for `python -m superlite`"""

import sys
import os

# Ensure project root is in path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.session import Session


def main():
    session = Session()
    return session.run(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main() or 0)
