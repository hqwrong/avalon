#! /usr/bin/python3

import sys,traceback
import pprint
import inspect

class CmdClient(object):
    def __init__(self, inst = None, prompt = "> "):
        self.prompt = prompt
        self.inst = inst
        self.commands = {}

        self.addcmd(self.help, "help")

    @staticmethod
    def splitargstr(argstr):
        argstr += " "
        in_string = None
        j = 0
        delimiter = []
        args = []
        for i in range(len(argstr)):
            if not delimiter and not in_string and argstr[i] in "\t\n ":
                tok = argstr[j:i+1].strip()
                if tok:
                    args.append(tok)
                    j = i
            elif in_string:
                if argstr[i] == in_string:
                    in_string = None
            elif argstr[i] == "'" or argstr[i] == '"':
                in_string = argstr[i]
            elif argstr[i] == "[":
                delimiter.append("]")
            elif argstr[i] == "{":
                delimiter.append("}")
            elif argstr[i] == "]" or argstr[i] == "}":
                if not delimiter or delimiter[-1] != argstr[i]:
                    raise NameError("syntax error at %dth char of [%s]"%(i, argstr))
                delimiter.pop()

        if delimiter or in_string:
            raise NameError("syntax error at end of [%s]" % argstr)

        return args

    @staticmethod
    def parseargstr(argstr):
        args = CmdClient.splitargstr(argstr)
        for i in range(len(args)):
            args[i] = eval(args[i], {}, {})
        return args

    @staticmethod
    def parsecmdline(l):
        tokens = l.split(None, 1)
        if not tokens:
            return None, None
        args = CmdClient.parseargstr(tokens[1] if len(tokens) > 1 else "")
        return tokens[0], args

    def addcmd(self, f, name = ""):
        realname = name or f.__name__
        if realname in self.commands:
            raise NameError(realname)
        self.commands[realname] = f

    def help(self, cmdname = ""):
        ok,similars = self.find_cmd(cmdname)
        cmds = [cmdname] if ok else similars
        for cmdname in cmds:
            cmdname,args = self.inspect_cmd(cmdname)
            print(cmdname,args)

    def inspect_cmd(self, cmdname):
        cmd = self.commands[cmdname]
        args = inspect.getargspec(cmd).args
        del args[0]             # remove `self' arg
        return cmdname, ",".join(args)
        
    def listcmd(self):
        return [cmdname for cmdname in self.commands]

    def has_cmd(self, cmdname):
        return cmdname in self.commands

    def find_cmd(self, cmdname):
        if cmdname in self.commands:
            return self.commands[cmdname],[]

        similars = []
        for n in self.commands:
            if n.startswith(cmdname):
                similars.append(n)

        if not similars:
            mindiff = 100000
            for n in self.commands:
                d = abs(len(n) - len(cmdname))
                for i in range(min(len(n), len(cmdname))):
                    if n[i] != cmdname[i]:
                        d += 1
                if d < mindiff:
                    similars = [n]
                    mindiff = d
                elif d == mindiff:
                    similars.append(n)

        return None, similars

    def docmd(self, cmdname, args):
        cmd,similars = self.find_cmd(cmdname)
        if not cmd:
            print("cmd not found:", cmdname)
            print("Did you mean this?")
            print("\t", ", ".join(similars))
            return

        if self.inst == None:
            result = cmd(*args)
        else:
            result = cmd(self.inst, *args)
        if result != None:
            pprint.pprint(result)
    
    def repl(self):
        while True:
            try:
                sys.stdout.write(self.prompt)
                sys.stdout.flush()
                l = sys.stdin.read(1)
                if not l: # eof
                    print("exit on EOF")
                    exit(0)
                if l == '\n':
                    continue
                l += sys.stdin.readline()
                l.strip()
                cmdname, args = self.parsecmdline(l)
                if not cmdname:
                    continue
                self.docmd(cmdname, args)

            except Exception as e:
                print("error occured", e, traceback.format_exc())
                continue


import urllib.request
import urllib.parse
import functools
import json
import http.cookies

usercmds = []
cmds = []
def addusercmd(f):
    usercmds.append((f.__name__, f))
    return f
def addcmd(f):
    cmds.append((f.__name__, f))
    return f

class AvalonClient(object):
    def __init__(self, addr):
        self._addr = addr
        self.uid = None
        self.roomid = None
        self.uid2name = {}

    def setuid(self, uid):
        if uid != None:
            for u in self.uid2name:
                if u.endswith(uid):
                    uid = u
                    break
            else:
                print("wrong uid", uid)
                raise NameError(uid)
        self.uid = uid

    def _request(self, path, **kargs):
        if self.uid:
            c = http.cookies.SimpleCookie()
            c["userid"] = self.uid
            cl_cookie = c.output(header = "")
        else:
            cl_cookie = ""
        request = urllib.request.Request(self._addr + path, headers = {"Cookie": cl_cookie})
        resp = urllib.request.urlopen(request, bytes(json.dumps(kargs), "utf-8"))
        c = http.cookies.SimpleCookie()
        sr_cookie = c.load(resp.getheader("Set-Cookie"))
        userid = c["userid"].value
        if userid not in self.uid2name:
            self.uid2name[userid] = "u"+ str(userid)
            print("new userid:", userid)
            
        body = ""
        try:
            body = json.loads(resp.read().decode("utf-8"))
        except:
            pass
        return body

    def _request_room(**kargs):
        if not self.roomid:
            raise NameError("roomid is nil")
        return self._request("/room", roomid = self.roomid, **kargs)

    @addcmd
    def listuid(self):
        return self.uid2name

    @addcmd
    def rep(self, loop, cmdname, *args):
        if type(loop) == int:
            for _ in range(loop):
                cl.docmd(cmdname, args[1:])
        else:                   # loop users
            for uid in loop:
                l = [uid]
                l.extend(args)
                cl.docmd(cmdname, l)

    @addcmd
    def newuser(self):
        self._request("/")
    
    ################### lobby
    @addusercmd
    def create(self):
        return self._request("/lobby", action="create")
    @addusercmd
    def setname(self, name):
        self.uid2name[self.uid] = name
        return self._request("/lobby", action="setname", username=name)
    @addusercmd
    def getname(self):
        return self._request("/lobby", action="getname")
    @addusercmd
    def join(self, roomid = None):
        return self._request("/lobby", action = "join", roomid = self.roomid)

    #################### room
    @addcmd
    def room(self, roomid):
        self.roomid = roomid
    @addusercmd
    def set(self, rule, enable = True):
        return self._request_room(action="set", rule=rule, enable=enable)
    @addusercmd
    def ready(self, enable = True):
        return self._request_room(action="ready", enable = enable)
    @addusercmd
    def stage(self, stagelist):
        return self._request_room(action="stage", stagelist=stagelist)
    @addusercmd
    def vote(self, approve=True):
        return self._request_room(action="vote", approve=approve)
    @addusercmd
    def begin(self):
        return self._request_room(action="begin_game")
    @addusercmd
    def info(self, version=0):
        return self._request_room(action="request", version = version)

cl = CmdClient(AvalonClient("http://localhost:8001"))
def wrapper(f):
    def _wrap(inst, userid = None, *args):
        inst.setuid(str(userid))
        ret = f(inst, *args)
        inst.setuid(None)
        return ret
    return _wrap

for name,f in usercmds:
    cl.addcmd(wrapper(f), name)
for name,f in cmds:
    cl.addcmd(f, name)

cl.repl()
