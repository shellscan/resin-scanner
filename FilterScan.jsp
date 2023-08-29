<%@ page import="com.caucho.server.webapp.WebApp" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.util.*" %>
<%@ page import="java.io.File" %>
<%@ page import="com.caucho.server.dispatch.*" %>
<%@ page import="com.caucho.server.cluster.ServletService" %>
<%@ page import="com.sun.org.apache.bcel.internal.classfile.JavaClass" %>
<%@ page import="java.io.FileOutputStream" %>
<%@ page import="com.sun.org.apache.bcel.internal.Repository" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%!
    class FilterBean {
        private String filterName;

        private String filterClass;

        private List<String> urlMapping;

        private Boolean safe;

        private List<Boolean> urlSafe;

        public List<Boolean> getUrlSafe() {
            return urlSafe;
        }

        public void setUrlSafe(List<Boolean> urlSafe) {
            this.urlSafe = urlSafe;
        }

        FilterBean() {

        }

        FilterBean(String filterName, String filterClass, boolean safe) {
            this.filterName = filterName;
            this.filterClass = filterClass;
            this.safe = safe;
        }

        FilterBean(String filterName, List<String> urlMapping) {
            this.filterName = filterName;
            this.urlMapping = urlMapping;
        }

        FilterBean(String filterName, List<String> urlMapping,List<Boolean> urlSafe) {
            this.filterName = filterName;
            this.urlMapping = urlMapping;
            this.urlSafe = urlSafe;
        }

        FilterBean(String filterName, String filterClass, List<String> urlMapping) {
            this.filterName = filterName;
            this.filterClass = filterClass;
            this.urlMapping = urlMapping;
        }

        public String getFilterName() {
            return filterName;
        }

        public void setFilterName(String filterName) {
            this.filterName = filterName;
        }

        public String getFilterClass() {
            return filterClass;
        }

        public void setFilterClass(String filterClass) {
            this.filterClass = filterClass;
        }

        public List<String> getUrlMapping() {
            return urlMapping;
        }

        public void setUrlMapping(List<String> urlMapping) {
            this.urlMapping = urlMapping;
        }

        public Boolean isSafe() {
            return safe;
        }

        public void setSafe(Boolean safe) {
            this.safe = safe;
        }
    }

    public Set<Map.Entry<String, FilterBean>> getEntry(WebApp context) throws Exception {
        Map<String, FilterBean> result = new LinkedHashMap<>();

        Field filterMapperField = context.getClass().getDeclaredField("_filterMapper");
        filterMapperField.setAccessible(true);
        FilterMapper filterMapper = (FilterMapper) filterMapperField.get(context);
        //获得filter manager
        FilterManager filterManager = filterMapper.getFilterManager();
        Set<Map.Entry<String, FilterConfigImpl>> entries = filterManager.getFilters().entrySet();
        for (Map.Entry<String, FilterConfigImpl> filterConfig : entries) {
            String filterName = filterConfig.getKey();
            FilterConfigImpl filter = filterConfig.getValue();
            String filterClass = filter.getFilterClass().getName();
            result.put(filterName, new FilterBean(filterName, filterClass, false));
        }

        //获得filter map
        Field filterMapField = filterMapper.getClass().getDeclaredField("_filterMap");
        filterMapField.setAccessible(true);
        List<FilterMapping> filterMap = (List) filterMapField.get(filterMapper);

        for (FilterMapping filterMapping : filterMap) {
            String urlPattern = filterMapping.getURLPattern();
            String filterName = filterMapping.getFilterName();
            FilterBean filterBean = result.get(filterName);
            if (filterBean != null) {
                List<String> urlMapping = filterBean.getUrlMapping();
                List<Boolean> urlSafe = filterBean.getUrlSafe();
                if (urlMapping == null) {
                    urlMapping = new ArrayList<>();
                }
                urlMapping.add(urlPattern);
                filterBean.setUrlMapping(urlMapping);
                result.replace(filterName, filterBean);
            } else {
                List<String> urlMapping = new ArrayList<>();
                urlMapping.add(urlPattern);
                result.put(filterName, new FilterBean(filterName, urlMapping, urlSafe));
            }
        }
        return result.entrySet();
    }

    public String getPath(HttpServletRequest req, String filename) {
        String path = req.getSession().getServletContext().getRealPath(filename);
        return path.substring(0, path.lastIndexOf(File.separator));
    }

    public void delFilter(WebApp context, String delFilterName) throws Exception {
        /**
         * 修改FilterMapper中的Filter信息
         */
        //获得FilterMapper
        Field filterMapperField = context.getClass().getDeclaredField("_filterMapper");
        filterMapperField.setAccessible(true);
        FilterMapper filterMapper = (FilterMapper) filterMapperField.get(context);
        //获得FilterMap
        Field filterMapField = filterMapper.getClass().getDeclaredField("_filterMap");
        filterMapField.setAccessible(true);
        List<FilterMapping> filterMap = (List<FilterMapping>) filterMapField.get(filterMapper);
        //新的FilterMap
        List<FilterMapping> newFilterMap = new ArrayList<>();
        for (FilterMapping filterMapping : filterMap) {
            if (!delFilterName.equals(filterMapping.getFilterName())) {
                newFilterMap.add(filterMapping);
            }
        }
        //替换FilterMapper中保存的FilterMap
        filterMapField.set(filterMapper, newFilterMap);
        /**
         * 修改FilterManager中保存的Filter信息
         */
        FilterManager filterManager = filterMapper.getFilterManager();
        Field filtersField = filterManager.getClass().getDeclaredField("_filters");
        filtersField.setAccessible(true);
        Map<String, FilterConfigImpl> filters = (Map<String, FilterConfigImpl>) filtersField.get(filterManager);
        Map<String, FilterConfigImpl> newFilters = new HashMap<>();
        for (Map.Entry<String, FilterConfigImpl> entry : filters.entrySet()) {
            if (!entry.getKey().equals(delFilterName)) {
                newFilters.put(entry.getKey(), entry.getValue());
            }
        }
        filtersField.set(filterManager, newFilters);
        Field instancesField = filterManager.getClass().getDeclaredField("_instances");
        instancesField.setAccessible(true);
        Map<String, Object> instances = (Map<String, Object>) instancesField.get(filterManager);
        Map<String, Object> newInstances = new HashMap<>();
        for (Map.Entry<String, Object> entry : instances.entrySet()) {
            if (!delFilterName.equals(entry.getKey())) {
                newInstances.put(entry.getKey(), entry.getValue());
            }
        }
        instancesField.set(filterManager, newInstances);
        //删除映射
        delUrlPattern(filterMapper, delFilterName, null);
    }

    //删除filter映射
    public void delUrlPattern(FilterMapper filterMapper, String delFilterName, String urlMap) throws Exception {
        Field filterMapField = filterMapper.getClass().getDeclaredField("_filterMap");
        filterMapField.setAccessible(true);
        ArrayList<FilterMapping> filterMap =
                (ArrayList<FilterMapping>) filterMapField.get(filterMapper);
        List<FilterMapping> newUrlPatterns = new ArrayList<>();
        if (urlMap != null) {
            for (FilterMapping mapping : filterMap) {
                String filterName = mapping.getFilterName();
                if (!filterName.equals(delFilterName)) {
                    newUrlPatterns.add(mapping);
                } else {
                    if (!mapping.getURLPattern().equals(urlMap)) {
                        newUrlPatterns.add(mapping);
                    }
                }
            }
        } else {
            for (FilterMapping mapping : filterMap) {
                if (!mapping.getFilterName().equals(delFilterName)) {
                    newUrlPatterns.add(mapping);
                }
            }
        }
        filterMapField.set(filterMapper, newUrlPatterns);
    }

    //清空缓存
    public void flushCache(WebApp context) throws Exception {
        //清除filterChainCache
        context.clearCache();
        //清除invocationCache
        Field serverField = context.getClass().getDeclaredField("_server");
        serverField.setAccessible(true);
        ServletService server = (ServletService) serverField.get(context);
        InvocationServer invocationServer = server.getInvocationServer();
        invocationServer.clearCache();
    }

    //dump class
    public void dumpClass(String className) {
        try {
            JavaClass javaClass = Repository.lookupClass(Class.forName(className));
            String simpleClassName = className.substring(className.lastIndexOf(".") + 1);
            FileOutputStream fos = new FileOutputStream(path + File.separator + simpleClassName + ".dump");
            javaClass.dump(fos);
        } catch (Exception e) {
        }
    }

    String path;
%>
<%
    //获得filter mapper
    WebApp context = (WebApp) application;

    String delFilterName = request.getParameter("delFilterName");
    String className = request.getParameter("className");
    String delUrlMapping = request.getParameter("delUrlMapping");
    path = getPath(request, "FilterScan.jsp").replaceAll("\\\\","\\\\\\\\");
    boolean runDelUrlMapping = delUrlMapping != null && !"".equals(delUrlMapping);
    if (runDelUrlMapping) {
        Field filterMapperField = context.getClass().getDeclaredField("_filterMapper");
        filterMapperField.setAccessible(true);
        FilterMapper filterMapper = (FilterMapper) filterMapperField.get(context);
        delUrlPattern(filterMapper, delFilterName, delUrlMapping);
        flushCache((WebApp) application);
        response.sendRedirect(request.getRequestURL().toString());
        return ;
    }

    boolean runDelFilter = delFilterName != null && !"".equals(delFilterName);
    if (runDelFilter) {
        //删除filter
        delFilter(context, delFilterName);
        //刷新缓存
        flushCache((WebApp) application);
        response.sendRedirect(request.getRequestURL().toString());
        return ;
    }

    boolean runDump = className != null && !"".equals(className);
    if (runDump) {
        dumpClass(className);
    }

    Set<Map.Entry<String, FilterBean>> filters = getEntry(context);
%>

<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resin-Filter列表</title>
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
<script type="text/javascript">
    var message = "慎重执行删除操作！！！删除操作不可逆，如果删除了正常的内容后想恢复，则需要重启OA。"
    alert(message)
</script>
<div class="content">
    <div class="">
        <div class="title">
            <h1>Resin-Filter列表</h1>
        </div>
        <table class="table">
            <tr class="table-header">
                <th>Filter名称</th>
                <th>Filter实际的类</th>
                <th>Filter过滤的接口</th>
                <th>操作</th>
            </tr>
            <%
                for (Map.Entry<String, FilterBean> entry : filters) {
                    FilterBean filter = entry.getValue();
                    List<String> urlMapping = filter.getUrlMapping();
            %>
            <tr class="table-safe">
                <td><%=filter.getFilterName() %></td>
                <td style="text-align: left;font-family: 'consolas';"><%=filter.getFilterClass() %></td>
                <td style="text-align: left;">
                    <%
                        if (urlMapping != null) {
                            for (int i = 0;i < urlMapping.size();i ++) {
                    %>
                    <div style="margin: 3px auto; border:2px solid #000;width: 98%;overflow: auto;"><%=urlMapping.get(i) %> &nbsp;&nbsp;
                        <button class="button" onclick="delUrlMapping('<%=filter.getFilterName()%>','<%=urlMapping.get(i)%>')">delete mapping</button>
                    </div>
                    <%
                            }
                        }
                    %>
                </td>
                <td><button class="button" onclick="delFilter('<%=filter.getFilterName()%>')">delete</button>
                    <button class="button" onclick="dump('<%=filter.getFilterClass()%>')">dump</button>
            </tr>
            <%
                }
            %>
        </table>

        <form id="filterForm" action="" method="get" style="display: none;">
            <input id="delFilterName" name="delFilterName">
            <input id="className" name="className">
            <input id="delUrlMapping" name="delUrlMapping">
        </form>
    </div>
</div>
</body>
<script type="text/javascript">
    function delFilter(filterName){
        var msg = "确认删除" + filterName + "吗?"
        if (confirm(msg)) {
            document.getElementById("delFilterName").value = filterName
            document.getElementById("className").value = null
            document.getElementById("delUrlMapping").value = null
            document.getElementById("filterForm").submit()
        }
    }
    function delUrlMapping(filterName,urlMapping){
        var msg = "确认删除" + filterName + "对" + urlMapping + "接口的拦截吗?"
        alert(msg)
        document.getElementById("delFilterName").value = filterName
        document.getElementById("className").value = null
        document.getElementById("delUrlMapping").value = urlMapping
        document.getElementById("filterForm").submit()
    }
    function dump(filterName){
        var msg = "dump出的文件存放在<%=path%>目录中"
        alert(msg)
        document.getElementById("delFilterName").value = null
        document.getElementById("className").value = filterName
        document.getElementById("delUrlMapping").value = null
        document.getElementById("filterForm").submit()
    }
</script>
</html>