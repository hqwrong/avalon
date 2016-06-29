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
        var hist = ""
        for (var i=resp.history.length-1;i>=0;i--) {
            hist += "<pre>" + resp.history[i] + "</pre>"
        }
        Ejoy("game-history").html(hist)
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
            var prompt = leader.username + " 正在准备" + Math.abs(resp.nstage) + "人提案."
            if (info.nstage < 0) {
                prompt += "(本次任务失败需至少两次反对票)"
            }
            Ejoy("stage_prompt").html(prompt)
        }
    }

    if (resp.mode == "audit") {
        var leader
        for (var i=0;i<resp.users.length;i++) {
            if (resp.users[i].userid == resp.leader) {
                leader = resp.users[i]
                break
            }
        }

        Ejoy("stage_prompt").html("请表决 " + leader.username + " 的提案")
        document.getElementsByClassName("vote-action")[0].style.display = "block"
        document.getElementsByClassName("stage-action")[0].style.display = "none"
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
            Ejoy("stage_prompt").html("请投票决定任务成功或失败")
            document.getElementsByClassName("vote-action")[0].style.display = "block"
            return
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

    var stage_list = [] 
    Ejoy("game-people").on("click", "people_item", function(select_dom){
        var user_id = select_dom.id;
        if (self.mode == "plan" && self.is_leader) {
            if (stage_list.indexOf(user_id) == -1) {
                if (stage_list.length >= Math.abs(gameinfo.nstage)) {
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
        if (self.mode == "plan" && self.is_leader && stage_list.length == Math.abs(gameinfo.nstage)) {
            var req = {
                roomid: room_number,
                status: 'game',
                action: 'stage',
                version: version,
                stagelist: stage_list,
            }

            Ejoy.postJSON('/room', req)
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

AvalonGame.fn.render_players = function(players, stage){
    var players_str = ""
    for(var i=0; i < players.length; i++){
        var player = players[i]
        var mark = 1
        if (stage.indexOf(player.uid) > -1)
            mark = 0
        var content = player.name
        if (player.identity)
            content += "[" + player.identity + "]"
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
