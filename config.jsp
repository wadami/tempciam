<%@ page import="org.json.simple.parser.JSONParser,
org.json.simple.JSONArray,
org.json.simple.parser.ParseException,
java.util.Map,
java.util.Set,
java.util.HashSet,
java.util.HashMap,
java.util.List,
java.util.ArrayList,
java.util.LinkedList,
java.util.LinkedHashMap,
java.io.StringWriter,
org.json.simple.parser.ContainerFactory,
org.json.simple.JSONObject,
org.json.simple.JSONArray,
org.json.simple.JSONValue,
javax.net.ssl.TrustManager,
javax.net.ssl.SSLContext,
javax.net.ssl.X509TrustManager,
java.lang.Integer,
java.net.HttpURLConnection,
javax.net.ssl.HttpsURLConnection,
java.net.URL,
org.apache.http.HttpResponse,
org.apache.http.client.HttpClient,
org.apache.http.client.config.RequestConfig,
org.apache.http.client.methods.HttpGet,
org.apache.http.client.methods.HttpPatch,
org.apache.http.client.methods.HttpPost,
org.apache.http.client.methods.HttpRequestBase,
org.apache.http.conn.ssl.SSLConnectionSocketFactory,
org.apache.http.entity.StringEntity,
org.apache.http.impl.client.HttpClients,
org.apache.http.ssl.SSLContextBuilder,
org.apache.http.ssl.SSLContexts,
javax.servlet.http.Cookie,
java.io.DataOutputStream,
java.io.InputStream,
java.io.BufferedReader,
java.lang.StringBuilder,
java.io.InputStreamReader,
java.net.URLEncoder" %>

<%!
	/*
	 * - Not using Mutual Authentication to retrieve Access Token and 
	 *   calling the Account Request endpoint (e.g. DataGov).
	 *   Might want to reconsider this.
	 * - This application requires valid certs everywhere.
	 * - Requires DataGov policy "Account Request Policy:Ownership-Requirement" 
	 *   changes to allow this non-tpp client to access the consent record.
	 *   Set Condition (e.g. to allow client_id=pingdirectory)
	 *     action.action_id =~ ['retrieve', 'delete'] && access_token.client_id != resource.audience 
	 *       && access_token.client_id != "pingdirectory"
	 */

        //PingFederate configuration
        String pfBaseUrl = "inject_pfBaseUrl";
        String pfRefDropoff = pfBaseUrl + "/ext/ref/dropoff";
        String pfRefPickup = pfBaseUrl + "/ext/ref/pickup?REF=";
        String pfRefAdapter = "inject_pfRefAdapter";
        String pfRefUsername = "inject_pfRefUsername";
        String pfRefPassword = "inject_pfRefPassword";

        String pfOBClientId = "inject_pfOBClientId"; //modified DataGov policy to allow pingdirectory client Account Request Policy:Ownership-Requirement
        String pfOBClientSecret = "inject_pfOBClientSecret";
        String pfOBClientScopes = "accounts%20user_consent";
        String pfOBFinancialId = "inject_pfOBFinancialId";

        String pfOBDefaultLocale = "en-AU";
        String pfOBDefaultLocaleVersion = "1.0";
        String dgUpdateConsentEndpoint = "inject_dgUpdateConsentEndpoint";
        String obAccountAPIEndpoint = "inject_obAccountAPIEndpoint";

        boolean isUseSSL = true;
        boolean isUseTLS = false;
        boolean isVerifyHostname = true;
        boolean useDebugging = true;
	
%>

<%!

ContainerFactory containerFactory = null;

ContainerFactory getContainerFactory()
{
	if(containerFactory == null)
	{
		//Setup JSON container settings
		ContainerFactory containerFactory = new ContainerFactory(){
			public java.util.List creatArrayContainer() {
				return new LinkedList();
			}

			public Map createObjectContainer() {
				return new LinkedHashMap();
			}
                        
		};
	}
	
	return containerFactory;
}
void disableHTTPSValidate()
{
	//Removes SSL certificate issue - this is not production code!
	try {
		// Create a trust manager that does not validate certificate chains
		TrustManager[] trustAllCerts = new TrustManager[]{
      			new X509TrustManager() {
          			public java.security.cert.X509Certificate[] getAcceptedIssuers() {
              				return null;
          			}
          			public void checkClientTrusted(
              				java.security.cert.X509Certificate[] certs, String authType) {
          			}
          			public void checkServerTrusted(
              				java.security.cert.X509Certificate[] certs, String authType) {
          			}
      			}	
    		};
    		SSLContext sc = SSLContext.getInstance("SSL");
    		sc.init(null, trustAllCerts, new java.security.SecureRandom());

    		HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());
  	} catch(Exception ex) {}
}

JSONObject pickupRef(HttpServletRequest request, Map<String, String> headers)  throws Exception {

	String ref = request.getParameter("REF");

	String refPickupEndpoint = pfRefPickup + ref;

	String refToken = executeHTTP(refPickupEndpoint, "GET", null, headers, false, null);

	if (refToken == null || refToken.trim().equals(""))
		return null;

	JSONParser parser = new JSONParser();
	JSONObject jsonRespObj = null;
	try {
		jsonRespObj = (JSONObject) parser.parse(refToken);
	} catch (ParseException e) {
		return null;
	}

	return jsonRespObj;
}

JSONObject getConsentDetails(String accessToken, HttpServletRequest request, String openbanking_intent_id) throws Exception {
	
	Map<String, String> headers = new HashMap<String, String>();
	headers.put("Accept", "application/json");
	headers.put("Content-Type", "application/json");
	headers.put("x-fapi-customer-ip-address", getIpAddr(request, "X-FORWARDED-FOR"));
	headers.put("x-fapi-financial-id", pfOBFinancialId);

	String authorizationHeader = "Bearer " + accessToken;

	String consentResponse = executeHTTP(dgUpdateConsentEndpoint + openbanking_intent_id, "GET", authorizationHeader, headers, false, null);

	if (consentResponse == null || consentResponse.trim().equals(""))
		return null;

	JSONParser parser = new JSONParser();
	JSONObject jsonRespObj = null;
	try {
		jsonRespObj = (JSONObject) parser.parse(consentResponse);
	} catch (ParseException e) {
		return null;
	}

	return jsonRespObj;
}

boolean isValidAccount(String accessToken, String userId, String accountId, HttpServletRequest request)
{
	List<String> userAccounts = getAccounts(accessToken, userId, request);
	
	if(userAccounts == null || userAccounts.size() == 0)
		return false;
	else
		return userAccounts.contains(accountId);
}

List<String> getAccounts(String accessToken, String userId, HttpServletRequest request)
{
	Map<String, String> headers = new HashMap<String, String>();
	headers.put("Accept", "application/json");
	headers.put("Content-Type", "application/json");
	headers.put("x-fapi-customer-ip-address", getIpAddr(request, "X-FORWARDED-FOR"));
	headers.put("x-fapi-financial-id", pfOBFinancialId);
	headers.put("x-user-id", userId);
	
	//the heroku app only requires a mock access token
    String accountResponse = null;
	try
	{
	   String fakeAccessToken = "e30=." + java.util.Base64.getEncoder().encodeToString(("{\"sub\": \"" + userId + "\"}").getBytes());
	   String authorizationHeader = "Bearer " + fakeAccessToken;

	   accountResponse = executeHTTP(obAccountAPIEndpoint, "GET", authorizationHeader, headers, false, null);
	}catch(Exception e)
	{
	}
	
	List<String> returnList = new ArrayList<String>();
	
	if (accountResponse == null || accountResponse.trim().equals(""))
		return returnList;
	
	JSONParser parser = new JSONParser();
	JSONObject jsonRespObj = null;
	try {
		jsonRespObj = (JSONObject) parser.parse(accountResponse);
	} catch (ParseException e) {
		return returnList;
	}

	if(jsonRespObj == null)
		return returnList;
		
	if(!jsonRespObj.containsKey("Data"))
		return returnList;
	
	JSONObject dataObject = (JSONObject) jsonRespObj.get("Data");
	
	if(!dataObject.containsKey("Account"))
		return returnList;
	
	JSONArray accountArray = (JSONArray) dataObject.get("Account");
	
	for(Object accountObj : accountArray)
	{
		JSONObject accountJSONObj = (JSONObject)accountObj;
		
		returnList.add(accountJSONObj.get("AccountId").toString());
	}
	
	return returnList;	
}

boolean updateConsentObject(String accessToken, HttpServletRequest request, String intentId, String consentAction, String consentPurpose, String actor, List<String> accounts, String subject, String consentText)  throws Exception {
	Map<String, String> headers = new HashMap<String, String>();
	headers.put("Accept", "application/json");
	headers.put("Content-Type", "application/json");
	headers.put("x-fapi-customer-ip-address", getIpAddr(request, "X-FORWARDED-FOR"));
	headers.put("x-fapi-financial-id", pfOBFinancialId);
	
	String authorizationHeader = "Bearer " + accessToken;

	JSONArray accountArray = new JSONArray();
	accountArray.addAll(accounts);
	
	//TODO need to do this better
	JSONObject dataObj = new JSONObject();
	dataObj.put("Status", consentAction);
	dataObj.put("ConsentPurpose", consentPurpose);
	dataObj.put("Actor", actor);
	dataObj.put("AddAccounts", accountArray);
	dataObj.put("Subject", subject);
	dataObj.put("ConsentText", consentText);
	dataObj.put("Locale", pfOBDefaultLocale);
	dataObj.put("Version", pfOBDefaultLocaleVersion);
	
	
	JSONObject consentObj = new JSONObject();
	consentObj.put("Data", dataObj);
	
	String dataStr = consentObj.toJSONString();

	String consentResponse = executeHTTP(dgUpdateConsentEndpoint + intentId, "PATCH", authorizationHeader, headers, false, dataStr);
	
	if(consentResponse == null)
		return false;
	
	return true;
}

String getAccessToken() throws Exception {
	Map<String, String> headers = new HashMap<String, String>();
	headers.put("Content-Type", "application/x-www-form-urlencoded");

	// TODO make this configurable
	String data = String.format(
			"client_id=%s&client_secret=%s&grant_type=client_credentials&scope=%s",
			pfOBClientId, pfOBClientSecret, pfOBClientScopes);

	String target = pfBaseUrl + "/as/token.oauth2";

	String tokenResp = executeHTTP(target, "POST", null, headers, false, data);

	if (tokenResp == null || tokenResp.trim().equals(""))
		return null;

	JSONParser parser = new JSONParser();
	JSONObject jsonRespObj = null;
	try {
		jsonRespObj = (JSONObject) parser.parse(tokenResp);
	} catch (ParseException e) {
		return null;
	}

	if (jsonRespObj == null || !jsonRespObj.containsKey("access_token"))
		return null;

	return jsonRespObj.get("access_token").toString();

}

String dropoffRef(HttpServletRequest request, HttpServletResponse response,
		Map<String, String> headers, String consentAction, List<String> accounts) throws Exception {
	String refDropoffEndpoint = pfRefDropoff;
	// Create a JSON Object containing user attributes
	JSONObject idpUserAttributes = new JSONObject();
	idpUserAttributes.put("subject", request.getParameter("openbanking_intent_id"));
	idpUserAttributes.put("result", consentAction);
	idpUserAttributes.put("requireMFA", "false");

	if(accounts != null)
		idpUserAttributes.put("accounts", accounts);

	String data = idpUserAttributes.toJSONString();

	String refJson = executeHTTP(refDropoffEndpoint, "POST", null, headers, false, data);

	JSONParser parser = new JSONParser();
	JSONObject jsonRespObj = (JSONObject) parser.parse(refJson);

	String referenceValue = (String) jsonRespObj.get("REF");

	return referenceValue;
}

String getIpAddr(HttpServletRequest request, String ipAddressHeader) {
	String ip = request.getHeader(ipAddressHeader);
	if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
		ip = request.getHeader(ipAddressHeader);
	}
	if (ip == null || ip.length() == 0 || "unknown".equalsIgnoreCase(ip)) {
		ip = request.getRemoteAddr();
	}
	return ip;
}

JSONObject parseJSON(String json)
{
        JSONParser parser = new JSONParser();
        JSONObject jsonRespObj = null;
        try {
                jsonRespObj = (JSONObject) parser.parse(json);
        } catch (ParseException e) {
                return null;
        }

        return jsonRespObj;
}

void setCookie(HttpServletRequest req, HttpServletResponse res, String name, String value)
{
	Cookie cookie = getCookie(req, name);
	
	if(cookie == null)
	{
		//create new cookie
		cookie = new Cookie(name, value);
	}
	else
	{
		cookie.setValue(value);
	}
	
	res.addCookie(cookie);
}

Cookie getCookie(HttpServletRequest req, String name)
{
	if(req.getCookies() == null)
		return null;
		
	for(Cookie cookie: req.getCookies())
	{
		if(cookie.getName().equals(name))
			return cookie;
	}
	
	return null;
		
}

String executeHTTP(String targetURL, String method, String authorization,
		Map<String, String> headers, boolean cleanParameters, String data)
		throws Exception {

	SSLContextBuilder sslCtx = SSLContexts.custom();
	
	SSLContext sslCtxBuild = sslCtx.build();

	SSLConnectionSocketFactory socketFactory = new SSLConnectionSocketFactory(
			sslCtxBuild, new String[]{"TLSv1.1","TLSv1.2"}, null, null);

	HttpClient client = HttpClients.custom()
			.setSSLSocketFactory(socketFactory).build();

	RequestConfig requestCfg = RequestConfig.custom().setConnectTimeout(60000).setSocketTimeout(60000).build();
	
	HttpRequestBase request = null;
	switch (method.toUpperCase()) {
	case "POST":
		HttpPost post = new HttpPost(targetURL);
		post.setEntity(new StringEntity(data));
		request = post;

		break;
	case "PATCH":
		HttpPatch patch = new HttpPatch(targetURL);
		patch.setEntity(new StringEntity(data));
		request = patch;

		break;
	default:
		HttpGet getreq = new HttpGet(targetURL);
		request = getreq;

	}

	if(authorization != null)
		request.addHeader("Authorization", authorization);
	
	if(headers != null)
	{
		// add request header
		for (String headerName : headers.keySet()) {				
			request.addHeader(headerName, headers.get(headerName));
		}
	}

	request.setConfig(requestCfg);
	
	HttpResponse response = client.execute(request);

	if(response == null)
	{			
		return null;
	}
	
	BufferedReader rd = new BufferedReader(new InputStreamReader(response
			.getEntity().getContent()));

	StringBuffer result = new StringBuffer();
	String line = "";
	while ((line = rd.readLine()) != null) {
		result.append(line);
	}
	
	return result.toString();

}

String executeHTTP(String targetURL, String method) throws Exception {
	return executeHTTP(targetURL, method, "");
}

String executeHTTP(String targetURL, String method, String authorization) throws Exception {
	return executeHTTP(targetURL, method, authorization, null, true);
}

String executeHTTP(String targetURL, String method, String authorization, Map<String, String> headers, boolean cleanParameters) throws Exception  {
	return executeHTTP(targetURL, method, authorization, headers, cleanParameters, "");
}

%>
