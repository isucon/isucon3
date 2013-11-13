if (!console.log) {
  console.log = function(){}
}

$(document).ready(function(){
    var api_key = $.cookie("api_key");
    console.log("api_key=" + api_key);

    if (api_key) {
        $('#signup_form').hide();
        $.ajax({
            type: "GET",
            url : "/me",
            data: {},
            success: function(user) {
                $('#user_name').text(user.name);
                $('#user_icon').attr("src", user.icon + "?size=m");
                $('#main_view').show().accordion({
                    heightStyle: "content",
                    header: "h3"
                });
                $('#head_timeline').click();
                show_timeline();
            },
            error: function(msg) {
                $.removeCookie("api_key");
                location.reload();
            }
        });
        $.ajax({
            type: "GET",
            url: "/follow",
            data: {},
            success: function(data) {
                $('#following_template').tmpl(data.users).appendTo('#following');
                $('.unfollow_user').click(unfollow_user);
            }
        });
    } else {
        $('#main_view').hide();
        $('#signup_form').dialog({
            modal: true,
            buttons: {
                "signup": function() {
                    $.ajax({
                        type: "POST",
                        url: "/signup",
                        data: {
                            name: $("#signup_name").val()
                        },
                        success: function(msg){
                            api_key = msg.api_key;
                            $.cookie("api_key", api_key);
                            $('#signup_ok').dialog();
                            $('#user_name').text(msg.name);
                            $('#user_icon').attr("src", msg.icon + "?size=m");
                            $('#signup_form').dialog("close");
                            $('#main_view').show().accordion({
                                heightStyle: "content",
                                header: "h3"
                            })
                            $('#head_timeline').click();
                            show_timeline();
                        }
                    });
                }
            }
        });
    }

    $('#icon_post').click(function() {
        $("#icon_file").upload('/icon', {}, function(msg) {
            var json = msg.replace(/<.*?>/g, ''); // xxx HTMLtagが混じってくることがあるので
            var data = JSON.parse(json)
            $('#user_icon').attr("src", data.icon + "?size=m");
            $('#head_timeline').click();
        });
    });
    $("#entry_post").click(function(){
        $("#entry_image").upload(
            '/entry',
            {
                publish_level: $("#entry_publish_level").val()
            },
            function(msg) {
                $("#head_timeline").click();
                $('#post_ok').dialog();
            }
        );
    });
    $("#show_api_key").click(function() {
        $("#api_key_view").text(api_key);
    });
})

var latest_entry;
var wait = 1000;
var wait_max = 60 * 1000;
var follow_user = function() {
    var id   = $(this).data("userid");
    var name = $(this).data("username");
    if (confirm("follow " + name + "?")) {
        $.ajax({
            type: "POST",
            url: "/follow",
            data: {
                target: id
            },
            success: function(data) {
                $('#following').empty();
                $('#following_template').tmpl(data.users).prependTo('#following');
                $('.unfollow_user').click(unfollow_user);
            }
        })
    }
};

var unfollow_user = function() {
    var id   = $(this).data("userid");
    var name = $(this).data("username");
    if (confirm("unfollow " + name + "?")) {
        $.ajax({
            type: "POST",
            url: "/unfollow",
            data: {
                target: id
            },
            success: function(data) {
                $('#following').empty();
                $('#following_template').tmpl(data.users).prependTo('#following');
                $('.unfollow_user').click(unfollow_user);
                $('#head_timeline').click();
            }
        })
    }
};

function show_timeline() {
    $("#loading").show();
    $("#loading_error").empty();
    $.ajax({
        type: "GET",
        url: "/timeline",
        data: {
            latest_entry: latest_entry
        },
        success: function(msg){
            wait = 1000;
            $("#loading").hide();
            latest_entry = msg.latest_entry;
            $('#entry_template').tmpl(msg.entries).prependTo('#timeline');
            $('.follow_user').unbind().click(follow_user);
            setTimeout( show_timeline, wait );
        },
        error: function(req, status, err) {
            $("#loading").hide();
            wait = wait * 2;
            if (wait_max < wait) {
                wait = wait_max;
            }
            $("#loading_error").text("loading error. retry after " + wait/1000 + " sec.");
            setTimeout( show_timeline, wait );
        }
    });
}

