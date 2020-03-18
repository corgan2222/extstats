<!DOCTYPE html
    PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
    <meta http-equiv="X-UA-Compatible" content="IE=Edge">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
    <meta HTTP-EQUIV="Expires" CONTENT="-1">
    <link rel="shortcut icon" href="images/favicon.png">
    <link rel="icon" href="images/favicon.png">
    <title>Test page</title>
    <link rel="stylesheet" type="text/css" href="index_style.css">
    <link rel="stylesheet" type="text/css" href="form_style.css">
    <script language="JavaScript" type="text/javascript" src="/state.js"></script>
    <script language="JavaScript" type="text/javascript" src="/general.js"></script>
    <script language="JavaScript" type="text/javascript" src="/popup.js"></script>
    <script language="JavaScript" type="text/javascript" src="/help.js"></script>
    <script type="text/javascript" language="JavaScript" src="/validator.js"></script>
    <script>


        var custom_settings = <% get_custom_settings(); %>;

        function initial() {
            show_menu();

            if (custom_settings.diversion_path == undefined)
                document.getElementById('diversion_path').value = "/tmp/default";
            else
                document.getElementById('diversion_path').value = custom_settings.diversion_path;
        }

        function applySettings() {
            /* Retrieve value from input fields, and store in object */
            custom_settings.diversion_path = document.getElementById('diversion_path').value;

            /* Store object as a string in the amng_custom hidden input field */
            document.getElementById('amng_custom').value = JSON.stringify(custom_settings);

            /* Apply */
            showLoading();
            document.form.submit();
        }

        function loadDivStats() {
            $.ajax({
                url: '/ext/uiDivStats/uidivstatstext.htm',
                dataType: 'text',
                error: function (xhr) {
                    setTimeout("loadDivStats();", 5000);
                },
                success: function (data) {
                    document.getElementById("divstats").innerHTML = data;
                }
            });
        }
    </script>


</head>

<body onload="initial();" class="bg">
    <div id="TopBanner"></div>
    <div id="Loading" class="popup_bg"></div>
    <iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
    <form method="post" name="form" action="start_apply.htm" target="hidden_frame">
        <input type="hidden" name="action_script" value="start_uiDivStats">
        <input type="hidden" name="current_page" value="extstats.asp">
        <input type="hidden" name="next_page" value="extstats.asp">
        <input type="hidden" name="group_id" value="">
        <input type="hidden" name="modified" value="0">
        <input type="hidden" name="action_mode" value="apply">
        <input type="hidden" name="action_wait" value="5">
        <input type="hidden" name="first_time" value="">
        <input type="hidden" name="action_script" value="">
        <input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
        <input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
        <input type="hidden" name="amng_custom" id="amng_custom" value="">

        <table class="content" align="center" cellpadding="0" cellspacing="0">
            <tr>
                <td width="17">&nbsp;</td>
                <td valign="top" width="202">
                    <div id="mainMenu"></div>
                    <div id="subMenu"></div>
                </td>
                <td valign="top">
                    <div id="tabMenu" class="submenuBlock"></div>
                    <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
                        <tr>
                            <td align="left" valign="top">
                                <table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3"
                                    class="FormTitle" id="FormTitle">
                                    <tr>
                                        <td bgcolor="#4D595D" colspan="3" valign="top">
                                            <div>&nbsp;</div>
                                            <div class="formfonttitle">extStats</div>
                                            <div style="margin:10px 0 10px 5px;" class="splitLine"></div>
                                            <div class="formfontdesc">
                                                <#1838#>
                                            </div>

    </form>

    <div>
        <table class="apply_gen">
            <tr class="apply_gen" valign="top">
            </tr>
        </table>
    </div>
    </td>
    </tr>
    </table>
    </td>
    </tr>
    </table>
    </td>
    <td width="10" align="center" valign="top"></td>
    </tr>
    </table>
    <div id="footer"></div>
</body>

</html>