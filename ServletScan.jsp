<%@ page import="java.io.File" %>

<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@page import="com.sun.org.apache.bcel.internal.classfile.JavaClass"%>
<%@page import="com.sun.org.apache.bcel.internal.Repository"%>
<%@ page import="java.io.FileOutputStream" %>
<%@ page import="com.caucho.server.webapp.WebApp" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.util.*" %>
<%@ page import="com.caucho.server.dispatch.*" %>
<%--
  Resin中Servlet扫描
  User: wufenglin
  Date: 2022/9/2
--%>
<%!
    //自定义ServletBean
    class ServletBean {
        // servlet名
        private String servletName;
        // servlet类
        private String servletClass;
        // 映射的地址
        private Set<String> urlMapping;
        // 是否初始化执行
        private Boolean loadOnStartup;

        public ServletBean(String servletName,String servletClass,Set<String> urlMapping,Boolean loadOnStartup){
            this.servletName = servletName;
            this.servletClass = servletClass;
            this.urlMapping = urlMapping;
            this.loadOnStartup = loadOnStartup;
        }

        public void removeUrlMapping(String mapping) {
            if (urlMapping.contains(mapping)) {
                urlMapping.remove(mapping);
            }
        }

        public String getServletName() {
            return servletName;
        }
        public void setServletName(String servletName) {
            this.servletName = servletName;
        }
        public String getServletClass() {
            return servletClass;
        }
        public void setServletClass(String servletClass) {
            this.servletClass = servletClass;
        }
        public Set<String> getUrlMapping() {
            return urlMapping;
        }
        public void setUrlMapping(Set<String> urlMapping) {
            this.urlMapping = urlMapping;
        }
        public Boolean getLoadOnStartup() {
            return loadOnStartup;
        }
        public void setLoadOnStartup(Boolean loadOnStartup) {
            this.loadOnStartup = loadOnStartup;
        }

    }
    //获取当前路径
    public String getPath(HttpServletRequest req,String filename) {
        String path = req.getSession().getServletContext().getRealPath(filename);
        return path.substring(0, path.lastIndexOf(File.separator));
    }
    //dump class
    public void dumpClass(String className,HttpServletRequest req){
        try {

            //TODO:这里用gs提供的Servlet注入会出现dump不出来的情况，回头再看看
            JavaClass javaClass = Repository.lookupClass(Class.forName(className));

            String simpleClassName = className.substring(className.lastIndexOf(".") + 1, className.length());
            FileOutputStream fos = new FileOutputStream(path + File.separator + simpleClassName + ".dump");
            javaClass.dump(fos);
        } catch(NullPointerException ne) {
            req.setAttribute("errmsg", "dump class 失败");
        } catch(ClassNotFoundException cfe) {
            cfe.printStackTrace();
            req.setAttribute("errmsg", "dump class 失败");
        } catch(Exception e) {

        }
    }
    public Object getField(Object object, String fieldString) throws NoSuchFieldException, IllegalAccessException {
        Field field = object.getClass().getDeclaredField(fieldString);
        field.setAccessible(true);
        return field.get(object);
    }

    public Boolean inServlet(String listenerString) {
        if (defaultServletMap.containsKey(listenerString)) {
            return true;
        }
        return false;
    }
    public Boolean inMapping(String servlet, String mapping) {
        if (defaultServletMap.containsKey(servlet)) {
            Set<String> strings = defaultServletMap.get(servlet);
            return strings.contains(mapping);
        }
        return false;
    }

    Map<String, Set<String>> defaultServletMap = new HashMap<String, Set<String>>();

    String path = "";
%>

<%
    //获取请求信息
    String className = request.getParameter("className");
    String urlMapping = request.getParameter("urlMapping");
    String servletName = request.getParameter("servletValue");
    //是否执行操作
    boolean runDump = className != null && !"".equals(className);
    boolean runDelUrlMapping = Boolean.valueOf(request.getParameter("runDelUrlMapping"));
    boolean runDelServlet = Boolean.valueOf(request.getParameter("runDelServlet"));

    //获取Context,servletMapper,servletManager
    WebApp servletContext = (WebApp) request.getSession().getServletContext();
    ServletMapper servletMapper = servletContext.getServletMapper();
    ServletManager servletManager = servletMapper.getServletManager();
    //获取servlets
    HashMap<String, ServletConfigImpl> servlets = servletManager.getServlets();

    //path处理
    path = getPath(request,"ServletScan.jsp").replaceAll("\\\\", "\\\\\\\\");

    //获取servletMapper中的urlPatterns
    HashMap<String, Set<String>> urlPatterns = (HashMap<String, Set<String>>) getField(servletMapper, "_urlPatterns");
    //获取servletMapper中的servletMap
    UrlMap<ServletMapping> servletMap = (UrlMap<ServletMapping>) getField(servletMapper, "_servletMap");
    //获取servletMapper中的servletNamesMap
    HashMap<String, ServletMapping> servletNamesMap = (HashMap<String, ServletMapping>) getField(servletMapper, "_servletNamesMap");
    //获取servletManager中的servletList
    ArrayList<ServletConfigImpl> servletList = (ArrayList<ServletConfigImpl>) getField(servletManager, "_servletList");
    //获取servletMap中的regexps
    ArrayList regexps = (ArrayList) getField(servletMap, "_regexps");

    //存储所有Servlet，key为Servlet名，value为Servlet实体
    HashMap<String, ServletBean> servletBeanHashMap = new HashMap<String, ServletBean>();
    //存储所有的Mapping，key为映射，value为Servlet实体
    HashMap<String, ServletBean> mappingToServlet = new HashMap<String, ServletBean>();

    //将所有servlet从servlets中取出来，并保存在自定义Map中
    for (Map.Entry<String, ServletConfigImpl> servlet : servlets.entrySet()) {
        String key = servlet.getKey();
        ServletConfigImpl value = servlet.getValue();

        Set<String> urlPattern = urlPatterns.get(key);
        ServletBean servletBean = new ServletBean(key, value.getClassName(), urlPattern, value.getLoadOnStartup() > 0);
        servletBeanHashMap.put(key, servletBean);

        if (urlPattern == null) {
            continue;
        }
        for (String map : urlPattern) {
            mappingToServlet.put(map, servletBean);
        }
    }

    //映射删除，这里其实只删除了regexps中的映射，还有一些映射信息没有删除
    //对于resin来说，只会来regexps中找匹配的路径，所以删掉这个容器中的变量就已经能阻止servlet路径访问了
    if (runDelUrlMapping) {
        for (int i = 0; i < regexps.size(); i++) {
            String regexpString = regexps.get(i).toString();
            String mapping = regexpString.substring(regexpString.indexOf("[") + 1, regexpString.indexOf("]"));
            if ( mapping.equals(urlMapping)) {
                //删除映射对应的servletBean中保存的映射，用于显示
                ServletBean servletBean = mappingToServlet.get(mapping);
                if (servletBean != null) {
                    servletBean.removeUrlMapping(mapping);
                    regexps.remove(i);
                }
                break;
            }
        }
        servletContext.clearCache();
    }

    //servlet删除，这里删除了servletManager和servletMapper中保存的所有servlet，包括servlet对应的映射
    if (runDelServlet) {
        //删除servletManager.servletList中对应的servlet
        for (int i = 0; i < servletList.size(); ++i) {
            if (servletList.get(i).getName().equals(servletName)) {
                servletList.remove(i);
                break;
            }
        }
        //删除servlet对应的所有映射
        ServletBean servletBean = servletBeanHashMap.get(servletName);
        Set<String> mapping = servletBean.getUrlMapping();
        for ( String m : mapping ) {
            servletNamesMap.remove(m);
            mappingToServlet.remove(m);
            for (int i = 0; i < regexps.size(); i++) {
                String regexpString = regexps.get(i).toString();
                String mappingString = regexpString.substring(regexpString.indexOf("[") + 1, regexpString.indexOf("]"));
                if ( mappingString.equals(m)) {
                    regexps.remove(i);
                    break;
                }
            }
        }
        //删除servletMapper._urlPatterns中对应的servlet
        urlPatterns.remove(servletName);
        //删除servletManager.servlets中对应的servlet
        servlets.remove(servletName);
        //删除自定义的集合
        servletBeanHashMap.remove(servletName);
        servletContext.clearCache();
    }
    if (runDump) {
        dumpClass(className,request);
    }


%>


<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resin-Servlet列表</title>
    <style>
        .body {
            width: 100%;
            margin: 0 auto;
            font-family: "consolas";
            background-color: #DCDCDC;
        }

        .content{
            width: 100%;
            margin-top: 50px;
        }

        .title {
            text-align: center;
        }

        .table {
            width: 80%;
            margin:0 auto;
            border-radius: 4px;
            padding: 5px;
        }
        .table-header{
            text-align: center;
        }
        .table-header th{
            border:2px solid #000000;
            border-radius: 1px;
        }
        .table-safe td{
            border:2px solid #000000;
            border-radius: 1px;
        }
        .table-safe{
            text-align: center;
        }
        .button{
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
            <h1>Resin-Servlet列表</h1>
        </div>
        <table  class="table">
            <tr class="table-header">
                <th>Servlet实际的类</th>
                <th>Servlet映射的接口</th>
                <th>是否在容器启动时运行</th>
                <th>操作</th>
            </tr>
            <%
                for (Map.Entry<String, ServletBean> entry: servletBeanHashMap.entrySet()) {
                    ServletBean servlet = entry.getValue();
                    Set<String> urlMappings = servlet.getUrlMapping();

                    if (urlMappings == null) {
                        continue;
                    }
            %>
            <tr class="table-safe" rowspan="<%=urlMappings.size()%>" >
                <td style="text-align: left;"><%=servlet.getServletClass() %></td>
                <td rowspan="1">
                    <%
                        int index = 0;
                        for(String url : urlMappings) {
                            index++;
                    %>
                    <t><%=url%></t>&nbsp;&nbsp;<button class="button" onclick="delUrlMapping('<%=url%>')">delete mapping</button>
                    <%=index != urlMappings.size() - 1 ? "":"<br/><br/>" %>

                    <%
                        }
                    %>
                </td>

                <td style="color: <%=servlet.getLoadOnStartup() ? "red":"green"%>"><%=servlet.getLoadOnStartup()? "是" : "否"%></td>
                <td><button class="button" onclick="delServlet('<%=servlet.getServletName()%>')">delete</button>
                    <button class="button" onclick="dump('<%=servlet.getServletClass()%>')">dump</button></td>
            </tr>
            <%
                }
            %>
        </table>

        <form id="delServletForm" action="" method="get" style="display: none;">
            <input id="servletValue" name="servletValue">
            <input id="urlMapping" name="urlMapping">
            <input id="runDelServlet" name = "runDelServlet" value="false">
            <input id="runDelUrlMapping" name = "runDelUrlMapping" value="false">
            <input id="className" name = "className">
        </form>
    </div>
</div>
</body>
<script type="text/javascript">

function delServlet(servletName){
	var msg = "确认删除 " + servletName + " 吗?"
	if (confirm(msg)) {
		document.getElementById("servletValue").value = servletName
		document.getElementById("urlMapping").value = null
		document.getElementById("runDelServlet").value = true
		document.getElementById("runDelUrlMapping").value = false
		document.getElementById("className").value = null
		document.getElementById("delServletForm").submit()
	}
}
function delUrlMapping(urlMapping){
	var msg = "确认删除 " + urlMapping + " 接口吗?"
	if (confirm(msg)) {
		document.getElementById("servletValue").value = null
		document.getElementById("urlMapping").value = urlMapping
		document.getElementById("runDelServlet").value = false
		document.getElementById("runDelUrlMapping").value = true
		document.getElementById("className").value = null
		document.getElementById("delServletForm").submit()
	}
}
function dump(className){
	var msg = "dump出的文件存放在<%=path%>目录中"
	alert(msg)
	document.getElementById("servletValue").value = null
	document.getElementById("urlMapping").value = null
	document.getElementById("runDelServlet").value = false
	document.getElementById("runDelUrlMapping").value = false
	document.getElementById("className").value = className
	document.getElementById("delServletForm").submit()
}
</script>
</html>
