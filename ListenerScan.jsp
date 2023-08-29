<%@ page import="com.caucho.server.webapp.WebApp" %>
<%@ page import="java.io.File" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@page import="com.sun.org.apache.bcel.internal.classfile.JavaClass" %>
<%@page import="com.sun.org.apache.bcel.internal.Repository" %>
<%@ page import="java.io.FileOutputStream" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="com.sun.org.apache.bcel.internal.util.SyntheticRepository" %>
<%@ page import="java.io.InputStream" %>
<%--
  Resin中Listener扫描
  User: wufenglin
  Date: 2022/9/19
--%>
<%!

    //获取当前路径
    public String getPath(HttpServletRequest req, String filename) {
        String path = req.getSession().getServletContext().getRealPath(filename);
        return path.substring(0, path.lastIndexOf(File.separator));
    }

    //dump class
    public void dumpClass(String className, HttpServletRequest req) {
        try {

            JavaClass javaClass = Repository.lookupClass(Class.forName(className));
            String simpleClassName = className.substring(className.lastIndexOf(".") + 1, className.length());
            FileOutputStream fos = new FileOutputStream(path + File.separator + simpleClassName + ".dump");
            javaClass.dump(fos);
        } catch (NullPointerException ne) {
            req.setAttribute("errmsg", "dump class 失败");
        } catch (ClassNotFoundException cfe) {
            System.out.println(cfe.toString());
            cfe.printStackTrace();
            req.setAttribute("errmsg", "dump class 失败");
        } catch (Exception e) {

        }
    }

    //反射获取属性，入参为要获取的属性所属的对象和属性名
    public Object getField(Object object, String fieldString) throws NoSuchFieldException, IllegalAccessException {
        Field field = object.getClass().getDeclaredField(fieldString);
        field.setAccessible(true);
        return field.get(object);
    }

    //反射设置属性，入参为要获取的属性所属的对象和属性名
    public void setField(Object object, String fieldString, Object value) throws NoSuchFieldException, IllegalAccessException {
        Field field = object.getClass().getDeclaredField(fieldString);
        field.setAccessible(true);
        field.set(object, value);
    }
    public Boolean in(String listenerString) {
        return false;
    }

    String path = "";
%>

<%

    //获取请求信息
    String delListenerName = request.getParameter("delListenerName");
    String dumpListenerName = request.getParameter("dumpListenerName");

    //是否执行操作
    boolean runDelListener = delListenerName != null && !"".equals(delListenerName);
    boolean runDumpListener = dumpListenerName != null && !"".equals(dumpListenerName);

    //path处理
    path = getPath(request, "ServletScan.jsp").replaceAll("\\\\", "\\\\\\\\");

    WebApp webApp = (WebApp) application;
    //获取所有的Listener
    ServletRequestListener[] requestListeners = webApp.getRequestListeners();

    //Listener删除，共由两个数据结构用来保存Listener
    if (runDelListener) {
        for (int i = 0; i < requestListeners.length; ++i) {
            if (requestListeners[i].toString().equals(delListenerName)) {
                ArrayList<ServletRequestListener> _requestListeners = (ArrayList<ServletRequestListener>) getField(webApp, "_requestListeners");
                _requestListeners.remove(requestListeners[i]);
                setField(webApp, "_requestListenerArray", _requestListeners.toArray(new ServletRequestListener[_requestListeners.size()]));
                requestListeners = webApp.getRequestListeners();
                break;
            }
        }
    }
    //Listener dump
    if (runDumpListener) {
        dumpClass(dumpListenerName.substring(0, dumpListenerName.indexOf("@")), request);
    }
    //刷新一下缓存确保删除操作生效
    webApp.clearCache();

%>

<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resin-Listener列表</title>
    <style>
        .body {
            width: 100%;
            margin: 0 auto;
            font-family: "consolas";
            background-color: #DCDCDC;
        }

        .content {
            width: 100%;
            margin-top: 50px;
        }

        .title {
            text-align: center;
        }

        .table {
            width: 80%;
            margin: 0 auto;
            border-radius: 4px;
            padding: 5px;
        }

        .table-header {
            text-align: center;
        }

        .table-header th {
            border: 2px solid #000000;
            border-radius: 1px;
        }

        .table-safe td {
            border: 2px solid #000000;
            border-radius: 1px;
        }

        .table-safe {
            text-align: center;
        }

        .button {
            font-size: medium;
            text-decoration: underline;
        }

        .button:hover {
            color: #6495ED;
            cursor: pointer;
        }
    </style>
</head>
<body class="body">
<%--<script type="text/javascript">--%>
<%--		var message = "慎重执行删除操作！！！删除操作不可逆，如果删除了正常的内容后想恢复，则需要重启OA。"--%>
<%--		alert(message)--%>


<%--</script>--%>
<div class="content">
    <div class="">
        <div class="title">
            <h1>Resin-Listener列表</h1>
        </div>
        <table class="table">
            <tr class="table-header">
                <th>Listener</th>
                <th>操作</th>
            </tr>
            <%
                for (int i = 0; i < requestListeners.length; ++i) {
            %>
            <tr class="table-safe" rowspan="<%=requestListeners.length%>"  style="color: <%=in(requestListeners[i].toString()) ? "green":"red"%>">
                <td style="text-align: left;"><%=requestListeners[i].toString()%>
                </td>

                <td>
                    <button class="button" onclick="delListener('<%=requestListeners[i].toString()%>')">delete</button>
                    <button class="button" onclick="dmpListener('<%=requestListeners[i].toString()%>')">dump</button>
                </td>
            </tr>
            <%
                }
            %>
        </table>

        <form id="delListenerForm" action="" method="get" style="display: none;">
            <input id="delListenerName" name="delListenerName">
        </form>
        <form id="dumpListenerForm" action="" method="get" style="display: none;">
            <input id="dmpListenerName" name="dumpListenerName">
        </form>
    </div>
</div>
</body>
<script type="text/javascript">

function delListener(listenerName){
	var msg = "确认删除 " + listenerName + " 吗?"
	if (confirm(msg)) {
		document.getElementById("delListenerName").value = listenerName
		document.getElementById("delListenerForm").submit()
	}
}

function dmpListener(listenerName){
	var msg = "dump出的文件存放在<%=path%>目录中"
	alert(msg)
	document.getElementById("dmpListenerName").value = listenerName
	document.getElementById("dumpListenerForm").submit()
}
</script>
</html>
