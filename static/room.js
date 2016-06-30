// 请求房间状态 ajax long pulling update 状态 
// 返回结果 更新 页面内容
// cookie 获取当前用户的user_id
// click 操作的 绑定

var room_number, userid, game;
var version = 0;

document.addEventListener("DOMContentLoaded", function(){
    userid = Number(Ejoy.getCookie('userid'));
    set_room_number();
    setTimeout(poll, 500)       // 0.5s
    bind_action()

    function set_room_number(){
        var pathname = location.pathname.split('/')
        room_number = parseInt(pathname[pathname.length - 1], 10)
        Ejoy('room_number').html(room_number) 
    }
    
    function poll(){
        var req = {
            roomid: room_number,
            action: 'poll',
            version: version
        }
        Ejoy.postJSON('/poll', req, function(resp){
            console.log('request', resp)
            if (resp == "abort") {
                return poll()
            }
            if (!resp.status) {
                return poll()
            }

            version = resp.version
            if (resp.status == "game" && !game) {
                prepare_clear()
                game = new AvalonGame(userid)
            }

            if (resp.status == "game") {
                game.update(resp)
            }else{
                update_room(resp)
            }

            poll()
        })        
    }

    function update_room(resp){
        if (resp.error) {return}

        // render users
        Ejoy('people_num').html(resp.users.length)
        render_players(resp.users)
        render_people_status(resp.users)
        render_prepare_action(resp.users)
        
        // render rules
        render_rules(resp.rules)

        render_game_status(resp.reason)
        render_begin_button(resp)
    }

    function render_game_status(reason) {
        if (reason) {
            Ejoy("game-status").html(reason)
        } else {
            Ejoy("game-status").html("")
        }
    }

    function render_begin_button(resp) {
        if (resp.owner != userid) {
            return
        }
        if (resp.can_game) {
            Ejoy("begin_button").html("开始")
        } else {
            Ejoy("begin_button").html("")
        }
    }

    function prepare_clear(){
        var prepare = document.getElementsByClassName('prepare')[0]
        var game  = document.getElementsByClassName('game')[0]
        prepare.style.display = "none"
        game.style.display = "block"
    }

    function render_players(players){
        var players_str = ""
        for(var i=0; i < players.length; i++){
            var player = players[i]
            var player_str = '<div class="people_item" id="' + 
                             player.uid + 
                             '"><span class="status_mark status_' + 
                             player.status +
                             '" style="color:' +
                             player.color +
                             '">' +
                             player.name +
                             '</span></div>';
            players_str += player_str;
        } 
        Ejoy('people').html(players_str);
    }

    function render_rules(rules){
        if(!rules){
            rules = []
        }
        var rules_str = ""
        rules_dom = document.getElementsByClassName("room_rule")[0].children
        for(var i = 0; i < rules.length; i++){
            rules_dom[rules[i]-1].className += " rule_enabled"
        }
    }

    function render_people_status(players){
       var prepare=0, watch=0, ready=0; 
       for(var i=0; i< players.length; i++){
           switch(players[i].status){
                case 0:
                    ready++;
                    break;
                case 1:
                    prepare++;
                    break;
                case 2:
                    watch ++;
                    break
           } 
       }

       var status = "";
       status += '<div><span>' + ready   + '</span>人准备好</div>' +
                 '<div><span>' + prepare + '</span>人正在准备</div>' +
                 '<div><span>' + watch   + '</span>人旁观</div>'
       Ejoy('people_status').html(status)
    }

    function render_prepare_action(players){
        var username="";
        var user_ready;
        for(var i=0; i< players.length; i++){
            var player = players[i]
            if(player.uid == userid){
                user_ready = player.status
                username = player.name
                break;
            }
        }
        var action = user_ready == 0 ? "取消准备" :"准备";
        Ejoy('action_button').html(action)
        Ejoy("name_button").html(username)
    }

    function bind_action(){
        Ejoy('room_rule').on('click', 'rule_item', function(select_dom){
            var rule_num = select_dom.dataset.rule
            var enabled  = !(select_dom.className.indexOf("rule_enabled") > -1)

            if(enabled){
                select_dom.className += " rule_enabled"
            }else{
                select_dom.className = "rule_item"
            }
            set_rule(rule_num, enabled)
        })

        Ejoy('name_button').on('click', function(e){
            var name = window.prompt("您的昵称:")
            if(!name){
                return alert("请输入名字");
            }
            console.log("set username", name)
            set_user_name(name)
        })

        Ejoy('action_button').on('click', function(e){
            set_ready()
        })

        Ejoy("begin_button").on("click", function (e){
            begin_game()
        })
    }

    function set_user_name(username){
        var req = {
            roomid: room_number,
            action: 'setname',
            version: version,
            username: username
        }
        Ejoy.postJSON('/room', req);
    }

    function set_rule(rule_num, enable){
        var req = {
            roomid: room_number,
            action: 'set_rule',
            version: version,

            rule: rule_num,
            enable: enable
        }
        Ejoy.postJSON('/room', req);

    }

    function set_ready(){
        var req = {
            roomid: room_number,
            action: 'ready',
            version: version,
            enable: Ejoy('action_button').val() == "准备",
        }
        Ejoy.postJSON('/room', req)
    }

    function begin_game() {
        var req = {
            roomid: room_number,
            action: "begin_game",
            version:version,
        }
        Ejoy.postJSON('/room', req)
    }
});
