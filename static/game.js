var stage_list = [] 

var AvalonGame = function(){
    this.status = "game";
    this.game_bind_action()
}

AvalonGame.fn = AvalonGame.prototype = {constructor: AvalonGame};

AvalonGame.fn.update_info = function(resp){
    this.mode = resp.mode
    this.is_leader = resp.leader == userid
    this.stage = resp.stage
}

AvalonGame.fn.update = function (resp){
    if (resp.error){
        return
    }
    
    gameinfo = resp
    self.update_info(resp)

    Ejoy("stage_title").html("共" + resp.evil_count + "个反方")
    Ejoy("stage_desc").html("第 "+ resp.round + " 个任务, 第 " + resp.pass + " 次提案" )

    this.render_role_info(resp)

    if (resp.history) {
        self.render_history(resp)
    }

    if (resp.mode == "plan") {
        self.render_players(resp.users, resp.stage)
        if (userid == resp.leader) {
            var info = resp
            var prompt = "请选出 " + Math.abs(info.nstage) + " 人";
            if (info.nstage < 0) {
                prompt += "(本次任务失败需至少两次反对票)"
            }
            Ejoy("stage_prompt").html(prompt)
            document.getElementsByClassName('stage-action')[0].style.display = "block"
            document.getElementsByClassName('vote-action')[0].style.display = "none"
            return
        } else {
            var info = resp
            document.getElementsByClassName('stage-action')[0].style.display = "none"
            document.getElementsByClassName('vote-action')[0].style.display = "none"

            var leader
            for (var i=0;i<resp.users.length;i++) {
                if (resp.users[i].uid == info.leader) {
                    leader = resp.users[i]
                    break
                }
            }
            var prompt = leader.name + " 正在准备" + Math.abs(resp.nstage) + "人提案."
            if (info.nstage < 0) {
                prompt += "(本次任务失败需至少两次反对票)"
            }
            Ejoy("stage_prompt").html(prompt)
        }
    }

    if (resp.mode == "audit") {
        var leader
        for (var i=0;i<resp.users.length;i++) {
            if (resp.users[i].uid == resp.leader) {
                leader = resp.users[i]
                break
            }
        }

        Ejoy("stage_prompt").html("请表决 " + leader.name + " 的提案. " + resp.votes.length + "人已表决")
        document.getElementsByClassName("stage-action")[0].style.display = "none"
        document.getElementsByClassName("vote-action")[0].style.display = resp.votes.indexOf(userid) == -1 ? "block" : "none"

        self.render_players(resp.users, resp.stage)
        return
    }

    if (resp.mode == "quest") {
        document.getElementsByClassName("stage-action")[0].style.display = "none"
        self.render_players(resp.users, resp.stage)

        if (resp.stage.indexOf(userid) == -1) {
            Ejoy("stage_prompt").html("请等待投票结果")
            document.getElementsByClassName("vote-action")[0].style.display = "none"
        } else {
            Ejoy("stage_prompt").html("*任务*阶段投票. " + resp.votes.length + "人已投票")
            document.getElementsByClassName("vote-action")[0].style.display = resp.votes.indexOf(userid) == -1 ? "block" : "none"
            return
        }
    }

    if (resp.mode == "assasin") {
        self.render_players(resp.users, [])
        if (resp.role == 5) {     // 刺客
            var info = resp
            Ejoy("stage_prompt").html("请找出梅林")
            document.getElementsByClassName('stage-action')[0].style.display = "block"
            document.getElementsByClassName('vote-action')[0].style.display = "none"
        } else {
            Ejoy("stage_prompt").html("等待刺客找出梅林")            
            document.getElementsByClassName('stage-action')[0].style.display = "none"
            document.getElementsByClassName('vote-action')[0].style.display = "none"
        }
    }

    if (resp.mode == "end") {
        var prompt = "游戏结束! "
        prompt += resp.winner + "方胜利"
        Ejoy("stage_prompt").html(prompt)

        self.render_players(resp.users, resp.stage)            
    }
}


AvalonGame.fn.game_bind_action = function(){
    self = this;
    Ejoy('role-button').on('click', function(e){
        var target = document.getElementsByClassName('role')[0]
        var ground = document.getElementsByClassName('ground')[0]
        if(target.className.indexOf('show') > -1){
            target.className = target.className.replace('show', '')
            ground.style.display = "block"

        }else{
            ground.style.display = "none"
            target.className += " show"
        }
    });  

    Ejoy("game-people").on("click", "people_item", function(select_dom){
        var user_id = Number(select_dom.id);
        if (self.mode == "plan" && self.is_leader || self.mode == "assasin" && gameinfo.role == 5) {
            var n = self.mode == "plan" ? Math.abs(gameinfo.nstage) : 1
            if (stage_list.indexOf(user_id) == -1) {
                if (stage_list.length >= n) {
                    return
                }
                stage_list.push(user_id);
            }
            else {
                Ejoy.array_remove(stage_list, user_id)
            }

            var status_mark = "status_0"
            if (stage_list.indexOf(user_id) == -1)
                status_mark = "status_1"
            var el = select_dom.children[0]
            el.className = el.className.replace(/status_\d/, status_mark)
        }
    }
                          );

    Ejoy('stage-commit').on('click', function(){
        if (self.mode == "plan" && self.is_leader || self.mode == "assasin" && gameinfo.role == 5) {
            var n = self.mode == "plan" ? Math.abs(gameinfo.nstage) : 1
            if (n == stage_list.length) {
                var req = {
                    roomid: room_number,
                    status: 'game',
                    action: self.mode == "plan" ? 'stage' : "assasin",
                    version: version,
                    stagelist: stage_list,
                }

                Ejoy.postJSON('/room', req)
            }
        }
    });

    var genvote = function (flag){
        return function ()  {
            if (self.mode == "audit" || (self.mode == "quest" && self.stage.indexOf(userid) != -1)) {
                var req = {
                    roomid: room_number,
                    status: 'game',
                    action: 'vote_' + self.mode,
                    version: version,
                    approve: flag,
                }

                Ejoy.postJSON('/room', req)
            }
        }
    }
    Ejoy('vote-yes').on('click', genvote(true));
    Ejoy('vote-no').on('click', genvote(false));
}

AvalonGame.fn.render_role_info = function(resp){
    self = this
    if (!resp.error) {
        Ejoy('role_name').html(resp.role_name)
        Ejoy('role-desc').html(resp.role_desc)
        var friends = resp.visible
        var friends_html = ""
        for(var i=0; i<friends.length; i++){
            var v = friends[i]
            friends_html += '<span>' + v.name + " : " + v.role_name  + '</span>' 
        } 

        Ejoy("role-visible").html(friends_html)
    }
}

AvalonGame.fn.render_history = function(resp){
    // todo: add history incrementally
    var hist = ""
    for (var i=resp.history.length-1;i>=0;i--) {
        var h = resp.history[i]
        
        hist += "<p class=" + ((h.htype == "任务失败" || h.htype=="提议流产")? "'hist-fail'":"'hist-succ'") + ">" + h.no + " " + h.htype + "</p>";
        hist += "<table class='hist-table'>"
        sorted = []
        for (var k in h) {
            sorted[sorted.length] = k
        }
        sorted.sort()
        for (var j in sorted) {
            k = sorted[j]
            if (k != "no" && k != "htype") {
                v = h[k]
                if (k == "n")
                    k = "否决票数:"
                else if (k == "leader") {
                    k = "提案者:"
                } else if (k == "no_votes") {
                    k = "否决者:"
                } else if (k == "yes_votes") {
                    k = "赞同者:"
                }
                hist += "<tr><td>" + k + "</td>" + "<td><div>"+ v + "</div></td></tr>"
            }
        }
        hist += "</table>"
    }
    Ejoy("game-history").html(hist)

}

AvalonGame.fn.render_players = function(players, stage){
    if (stage) {
        stage_list = stage
    }
    stage = stage_list
    var players_str = ""
    for(var i=0; i < players.length; i++){
        var player = players[i]
        var mark = 1
        if (stage_list.indexOf(player.uid) > -1)
            mark = 0
        var content = player.name
        if (player.role_name)
            content += "[" + player.role_name + "]"
        players_str += '<div class="people_item" id="' + 
            player.uid + 
            '"><span class="status_mark status_' + 
            mark +
            '" style="color:' +
            player.color +
            '">' +
            content +
            '</span></div>';
    } 
    Ejoy('game-people').html(players_str);
}
