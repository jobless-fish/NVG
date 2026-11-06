"""Portable database connection; Docker DNS default, no host PC address."""
import os
from pymongo import MongoClient

def database():
    return MongoClient(os.environ.get("MONGO_URI","mongodb://mongo:27017"),serverSelectionTimeoutMS=5000)[os.environ.get("MONGO_DATABASE","nodeverse")]
