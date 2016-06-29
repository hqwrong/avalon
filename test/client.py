#! /usr/bin/python3

import sys,traceback
import pprint
import inspect

class CmdClient(object):
    def __init__(self, inst = None, prompt = "> "):
        self.prompt = prompt
        self.inst = inst
        self.commands = {}

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

    def docmd(self, cmdname, *args):
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
        return result

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
                result = self.docmd(cmdname, *args)
                if result != None:
                    pprint.pprint(result)

            except Exception as e:
                print("error occured", e, traceback.format_exc())
                continue


import urllib.request
import urllib.parse
import json
import http.cookies

def addcmd(f):
    f._avalon_cmd = True
    return f

class AvalonClient(object):
    def __init__(self, addr):
        self._addr = addr
        self.uid = None
        self.roomid = None
        self.uid2name = {}
        self.cl = None

    def repl(self):
        cl = CmdClient()
        self.cl = cl
        for k in dir(self):
            v = getattr(self, k)
            if hasattr(v, "_avalon_cmd"):
                cl.addcmd(v)
        return cl.repl()

    def _request(self, path, uid = None, **kargs):
        if uid:
            c = http.cookies.SimpleCookie()
            c["userid"] = uid
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
            
        body = ""
        try:
            body = json.loads(resp.read().decode("utf-8"))
        except:
            pass
        return body

    def _request_room(self, uid, **kargs):
        if not self.roomid:
            raise NameError("roomid is nil")
        return self._request("/room", uid, roomid = self.roomid, **kargs)

    def check(self, tmpl):
        info = self.info()
        for k,v in tmpl.items():
            if info.get(k) != v:
                pprint.pprint(info)
                print("FAILED. [%s] %s != %s"%(k, info.get(k), v))
                raise Exception()

    @addcmd
    def listuid(self):
        return self.uid2name

    @addcmd
    def newuser(self):
        self._request("/")

    @addcmd
    def help(self):
        self.cl.help()
    
    ################### lobby
    @addcmd
    def create(self, uid):
        ret = self._request("/lobby", uid, action="create")
        self.roomid = ret["room"]
        return ret
    @addcmd
    def setname(self, uid, name):
        self.uid2name[uid] = name
        return self._request("/lobby", uid, action="setname", username=name)
    @addcmd
    def getname(self, uid):
        return self._request("/lobby", uid, action="getname")

    #################### room
    @addcmd
    def room(self, roomid):
        self.roomid = roomid
    @addcmd
    def join(self, uid):
        return self._request("/" + str(self.roomid), uid)
    @addcmd
    def set_rule(self, uid, rule, enable = True):
        return self._request_room(uid, action="set_rule", rule=rule, enable=enable)
    @addcmd
    def ready(self, uid, enable = True):
        return self._request_room(uid, action="ready", enable = enable)
    @addcmd
    def stage(self, uid, stagelist):
        return self._request_room(uid, action="stage", stagelist=stagelist)
    @addcmd
    def vote_audit(self, uid, approve=True):
        return self._request_room(uid, action="vote_audit", approve=approve)
    @addcmd
    def vote_quest(self, uid, approve=True):
        return self._request_room(uid, action="vote_quest", approve=approve)
    @addcmd
    def begin(self, uid):
        return self._request_room(uid, action="begin_game")
    @addcmd
    def info(self, uid=1, version=0):
        return self._request_room(uid, action="request", version = version)
    @addcmd
    def assasin(self, uid, tuid):
        return self._request_room(uid, action="assasin", tuid = tuid)

    ################# combined commands
    @addcmd
    def mkroom(self, n = 6, rules = []):
        for _ in range(n):
            self.newuser()

        uids = [uid for uid in self.listuid()]
        owner=uids[0]
        roomid = self.create(owner)["room"]
        self.room(roomid)
        for uid in uids:
            self.join(uid)
            self.ready(uid)
        for r in rules:
            self.set_rule(owner, r, True) # 梅林与刺客
        self.begin(owner)
        return uids
        
    @addcmd
    def doaudit(self, n_audit_no = 0, stagelist = None):
        info = self.info()
        uids = [u["uid"] for u in info["users"]]
        if not stagelist:
            stagelist = [uids[i] for i in range(info["nstage"])]
        self.stage(info["leader"], stagelist)

        for i,uid in enumerate(uids):
            self.vote_audit(uid, False if i < n_audit_no else True)
    @addcmd
    def doquest(self, n_vote_no = 0):
        info = self.info()
        uids = [u["uid"] for u in info["users"]]
        for i, uid in enumerate(uids):
            self.vote_quest(uid, False if i < n_vote_no else True)

def test1(cl):
    n = 6
    cl.mkroom(n, [1])           # 梅林规则

    cl.check({"pass":1, "round":1, "nsuccess":0})

    cl.doaudit(0)
    cl.doquest(0)
    cl.check({"pass":1, "round":2, "nsuccess":1})

    cl.doaudit(int(n/2) + 1)
    cl.doaudit(int(n/2) - 1)
    cl.check({"pass":2, "round":2})
    cl.doquest(1)
    cl.check({"pass":1, "round":3, "nsuccess":1})

    for _ in range(5):          # 流产
        cl.doaudit(n)
    cl.check({"pass":1, "round":4, "nsuccess":1})
    

    cl.doaudit(0)
    cl.doquest(0)

    cl.doaudit(0)
    cl.doquest(n)

    cl.check({"mode":"assasin"})
    for u in cl.info()["users"]:
        role = cl.info(u["uid"])["role"]
        if role == 1:
            meilin = u["uid"]
        elif role == 5:
            assasor = u["uid"]
    cl.assasin(assasor, meilin)
    cl.check({"mode":"end", "winner":"evil"})

    print("梅林规则测试 通过!")

if __name__ == "__main__":
    import sys
    if len(sys.argv) <= 1 or sys.argv[1] not in ("repl", "test"):
        print("Usage: %s repl|test"%sys.argv[0])
        sys.exit()
    cl = AvalonClient("http://localhost:8001")
    if sys.argv[1] == "repl":
        cl.repl()
    else:
        test1(cl)
        print("测试 通过!")




