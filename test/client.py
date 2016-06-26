#! /usr/bin/python3


import urllib.request
import sys

cmds = {}

def addcmd(name, *argtempls):
    def _wrapper(f, *args):
        if len(args) != len(argtempls):
            print("wrong #args")
            return
        for i, tmp in enumerate(argtempls):
            if tmp == "int":
                args[i] = int(args[i])

while True:
    print("> ")
    l = sys.stdin.readline()
    if not l:
        break
    words = l.split()
    if len(words) == 0:
        continue
    c = words[0]
    if c not in cmds:
        print("invalid cmd")
        cmds.help()
    cmds[c](*words[1:])

print("goodbye.")
urllib.request.urlopen("localhost:8001")
