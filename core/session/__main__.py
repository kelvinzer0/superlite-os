"""Entry point for python -m core.session"""
from . import Session

if __name__ == "__main__":
    session = Session()
    session.run()
