<?xml version="1.0" ?>
<!-- 

http://code.msdn.microsoft.com/HVRemote
See this site for license terms, a copy of the documentation and change history.

By:                 John Howard
Blog:               http://blogs.technet.com/jhoward
Originally Created: October/November 2008 while on vacation!
Last Updated:       9th September 2013
About:              Script for configuring Hyper-V Remote Management

-->
<package>
 <job>
 <?job error="True" debug="True" ?>

  <!-- Global object for scripting against WMI. Added as a reference to get constants -->
  <object id="oSWbemLocator" progid="WbemScripting.SWbemLocator" reference="true"/>

  <!-- Reference to AZMan (azroles.dll) -->
  <reference object="AzRoles.AzAuthorizationStore"/>

  <!-- Start of the HVRemote script. This is in VBScript for historic reasons as prior to Windows Server 2012
       there is no PowerShell environment available in server core installations. This script is designed
       to support configuration of Remote Management on all versions of Hyper-V from Windows Server 2008 onwards.
       This includes full and server core installations, and Hyper-V Server. As from version 1.03 (not public release)
       it includes support for Windows 8 Client and Windows Server 2012 as well. Version 1.08 onwards also
       supports Windows 8.1/Windows Server 2012 R2 RTM -->

  <script language="VBscript">

   <![CDATA[

    Option Explicit                  ' Must declare our variables
    On error resume next             ' We do the error handling ourselves

    Const VERSION = "1.08"   
    Const RELEASE_DATE = "9th Sept 2013"
    Const BLOG_URL_TO_THIS_TOOL = "http://tinyurl.com/kvov7c"
    Const CODE_MSDN_URL = "http://code.msdn.microsoft.com/HVRemote"

    ' ADs Constants ' Alternate to <reference object="ADs"/> which didnt' work on one box
    Const ADS_ACETYPE_ACCESS_ALLOWED = 0
    Const ADS_ACETYPE_ACCESS_DENIED  = 1

    Const ADS_ACEFLAG_FAILED_ACCESS = 128
    Const ADS_ACEFLAG_INHERIT_ACE = 2
    Const ADS_ACEFLAG_INHERIT_ONLY_ACE = 8
    Const ADS_ACEFLAG_INHERITED_ACE = 16
    Const ADS_ACEFLAG_NO_PROPAGATE_INHERIT_ACE = 4
    Const ADS_ACEFLAG_SUCCESSFUL_ACCESS = 64
    Const ADS_ACEFLAG_VALID_INHERIT_FLAGS = 31

    ' Function return code
    Const NO_ERROR = 0
    Const ERROR_ALREADY_PRESENT = -1  ' Custom RC if ACE already present in DACL when adding it
    Const ERROR_NOT_PRESENT = -2      ' Custom RC if ACE is not present in DACL when removing it
    Const SE_DACL_PRESENT = 4

    ' Namespaces we are interested in working with for Hyper-V Remote Management. Note is bitmask
    Const NAMESPACE_CIMv2            = &H1
    Const NAMESPACE_VIRTUALIZATION   = &H2
    Const NAMESPACE_VIRTUALIZATIONV2 = &H4

    ' Return error when group or user not found
    Const ERROR_OBJECT_NOT_FOUND = &H80041002

    ' For machine DCOM callback access restriction
    Const HKEY_LOCAL_MACHINE = &H80000002
    Const MACHINE_RESTRICTION_PATH = "Software\Microsoft\Ole"
    Const MACHINE_ACCESS_RESTRICTION_KEY  = "MachineAccessRestriction"
    Const MACHINE_LAUNCH_RESTRICTION_KEY  = "MachineLaunchRestriction"
    Const ACCESS_PERMISSION_LOCAL_ACCESS  = 2 
    Const ACCESS_PERMISSION_REMOTE_ACCESS = 4 
    Const ACCESS_PERMISSION_LOCAL_ACTIVATION = 8
    Const ACCESS_PERMISSION_REMOTE_ACTIVATION = 16
    Const ACCESS_PERMISSION_OTHER_FLAG    = 1 ' No idea but always needs to be set

    ' WMI Namespace Access Rights Constants
    ' http://msdn.microsoft.com/en-us/library/aa392710(VS.85).aspx
    Const WBEM_ENABLE            = &h1 
    Const WBEM_METHOD_EXECUTE    = &h2 
    Const WBEM_FULL_WRITE_REP    = &h4 
    Const WBEM_PARTIAL_WRITE_REP = &h8 
    Const WBEM_WRITE_PROVIDER    = &h10 
    Const WBEM_REMOTE_ACCESS     = &h20 
    Const READ_CONTROL           = &h20000 
    Const WRITE_DAC              = &h40000 


    ' Well known SIDs
    ' http://support.microsoft.com/kb/243330. Not hard coded group name as it is localised. SID is universal though.
    Const SID_EVERYONE                    = "S-1-1-0"
    Const SID_ANONYMOUS                   = "S-1-5-7"
    Const SID_BUILTIN_ADMINISTRATORS      = "S-1-5-32-544"
    Const SID_PERFORMANCE_LOG_USERS       = "S-1-5-32-559"
    Const SID_DISTRIBUTED_COM_USERS       = "S-1-5-32-562"
    Const SID_HYPERV_ADMINISTRATORS       = "S-1-5-32-578"

    ' Mode we are operating in: Server or Client configuration
    Const HVREMOTE_MODE_UNKNOWN = 0
    Const HVREMOTE_MODE_CLIENT = 1
    Const HVREMOTE_MODE_SERVER = 2
    
    ' Debug Mode    
    Const DBG_NONE      = 0
    Const DBG_STD       = 1
    Const DBG_EXTRA     = 2

    ' Are we configuring Anonymous DCOM (client)
    Const HVREMOTE_CLIENTOP_ANONDCOM_NONE   = 0
    Const HVREMOTE_CLIENTOP_ANONDCOM_GRANT  = 1
    Const HVREMOTE_CLIENTOP_ANONDCOM_REVOKE = 2

    ' Are we adding or removing a user (Server)
    Const HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE   = 0
    Const HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD    = 1
    Const HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE = 2

    ' Are we updating AZMan (Server)
    Const HVREMOTE_SERVEROP_AZMANUPDATE_OFF = 0
    Const HVREMOTE_SERVEROP_AZMANUPDATE_ON  = 1

    ' Are we configuring DCOM Permissions (Server)
    Const HVREMOTE_SERVEROP_DCOMPERMISSIONS_OFF = 0
    Const HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON  = 1

    ' Equivalent to netsh advfirewall firewall set rule group="Hyper-V" new enable=yes
    Const HVREMOTE_SERVEROP_FIREWALL_HYPERV_NONE = 0
    Const HVREMOTE_SERVEROP_FIREWALL_HYPERV_ALLOW = 1
    Const HVREMOTE_SERVEROP_FIREWALL_HYPERV_DENY = 2
    Const HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_V1   = "@%systemroot%\system32\vmms.exe,-99010"  ' 2008
    Const HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_Win7 = "@%systemroot%\system32\vmms.exe,-210"    ' 2008 R2 & Windows 8/2012

    ' Equivalent to netsh advfirewall firewall set rule group="Hyper-V Management Clients" new enable=yes
    Const HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_NONE = 0
    Const HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_ALLOW = 1
    Const HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_DENY = 2
    Const HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE = "@%ProgramFiles%\Hyper-V\SnapInAbout.dll,-211"

    ' Client DA (New 1.03)
    Const HVREMOTE_CLIENTOP_FIREWALL_DA_NONE = 0
    Const HVREMOTE_CLIENTOP_FIREWALL_DA_ENABLE = 1
    Const HVREMOTE_CLIENTOP_FIREWALL_DA_DISABLE = 2

    ' Client tracing (New 0.7)
    Const HVREMOTE_CLIENTOP_TRACING_NONE = 0
    Const HVREMOTE_CLIENTOP_TRACING_ON = 1
    Const HVREMOTE_CLIENTOP_TRACING_OFF = 2

    ' Installed OS Type (New 1.03)
    Const HVREMOTE_INSTALLED_OS_UNKNOWN = 0
    Const HVREMOTE_INSTALLED_OS_CLIENT = 1
    Const HVREMOTE_INSTALLED_OS_SERVER = 2

    ' Firewall Profile Type
    Const NET_FW_PROFILE2_DOMAIN = 1
    Const NET_FW_PROFILE2_PRIVATE = 2
    Const NET_FW_PROFILE2_PUBLIC = 4

    ' Firewall Protocol
    Const NET_FW_IP_PROTOCOL_TCP = 6
    Const NET_FW_IP_PROTOCOL_UDP = 17
    Const NET_FW_IP_PROTOCOL_ICMPv4 = 1
    Const NET_FW_IP_PROTOCOL_ICMPv6 = 58

    ' Firewall Direction
    Const NET_FW_RULE_DIR_IN = 1
    Const NET_FW_RULE_DIR_OUT = 2

    ' Firewall Action
    Const NET_FW_ACTION_BLOCK = 0
    Const NET_FW_ACTION_ALLOW = 1

    ' Authorisation store
    Const AUTH_STORE_PATH = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization"
    Const AUTH_STORE_KEY  = "StoreLocation"
    Const AUTH_STORE_SERVICE = "ServiceApplication"

    ' To determine elevation
    Const ELEVATION_UNKNOWN = 0
    Const ELEVATION_NO = 1
    Const ELEVATION_YES = 2

    ' What OS release are we running on
    Const WIN_UNKNOWN = 0
    Const WIN_6       = 6
    Const WIN_7       = 7
    Const WIN_8       = 8
    Const WIN_8POINT1 = 9
    Const WIN_LATER   = 10   

    ' For calling TestService()
    Const SERVICE_TEST_PRESENT = 1
    Const SERVICE_TEST_RUNNING = 2

    ' Global declarations                        
    Dim glInstalledOS                            ' What is the current operating system, a client or a server?
    Dim glClientServerMode                       ' Operating in client or server mode
    Dim gszServerOpAddOrRemoveUserName           ' Server: /add and /remove: Username to update
    Dim gszServerOpAddOrRemoveDomainName         ' Server: /add and /remove: Domain of user to update
    Dim glServerOpAddRemoveUser                  ' Server: Are we adding or removing a user?
    Dim glServerOpAZManUpdate                    ' Server: Are we updating AZMan?
    Dim glServerOpDCOMPermissions                ' Server: Are we updating DCOM permissions?
    Dim glServerOpNameSpacesToUse                ' Server: Which namespaces are we using
    Dim glClientOpAnonDCOMMode                   ' Client: Remote access to DCOM for anonymous logon
    Dim glClientOpTracing                        ' Client: Turning tracing on or off
    Dim glDebugLevel
    Dim gbShowMode                               ' Are we in "Show" mode displaying information
    Dim gbTestConnectivity                       ' Are we in "Show" mode and also testing connectivity to gszRemoteComputerName?
    Dim glServerOpFirewallHyperV                 ' Are we changing rule group Hyper-V
    Dim glClientOpFirewallHyperVMgmtClient       ' Are we changing rule group Hyper-V Management Clients
    Dim glClientOpFirewallDA                     ' Are we changing the inbound client FW rules to be DA capable (or not)
    Dim glOSRelease                              ' What is the OS release we are running on WIN_6, _7, _....
    Dim gszAuthStoreServiceApplication           ' Service application in the authorization store
    Dim gszAuthStore                             ' Authorization store file
    Dim gbComputerIsWorkgroup                    ' If we are in a workgroup
    Dim gszLocalComputerName                     ' Name of the local computer
    Dim gszLocalComputerDomainName               ' Domain name of local computer (blank if in workgroup)
    Dim gbIsRoleInstalled                        ' Is the Hyper-V Role installed on this machine?
    Dim gbIsSCVMM                                ' Is the VMM Agent installed on this machine?
    Dim gszRoleAssign                            ' Which role assignment we're using in the AZMan store
    Dim gbVersionCheck                           ' Are we checking if there is a later version?
    Dim glElevated                               ' Is the script running elevated (unknown/no/yes)
    Dim gbIsFirewallRunning                      ' Is the windows firewall service running?
    Dim glWarns                                  ' Number of warnings
    Dim gszWarns                                 ' Summary of the warnings
    Dim gszRemoteComputerName                    ' When testing connectivity
    Dim glRemoteOSRelease                        ' WIN_6 etc. Of remote machine
    Dim goRemoteCIMv2                            ' Connection to remote machine for cimv2 namespace
    Dim goRemoteVirtualization                   ' Connection to remote machine to virtualization namespace
    Dim goRemoteVirtualizationv2                 ' Connection to remote machine to virtualization\v2 namespace if remote target is Windows 8
    Dim goRemoteWin32CS                          ' win32_computersystem WMI object for remote machine
    Dim goRemoteWin32OS                          ' win32_operatingsystem WMI object for remote machine
    Dim glRemoteInstalledOS                      ' Is the remote OS a client or a server?
    Dim gbAnonDCOMAllowed                        ' Is anonymous DCOM allowed
    Dim glTestsPassed                            ' Number of tests passed
    Dim gbExplicitAddRemove                      ' For Windows 8, allow option to add user explicitly rather than using Hyper-V Administrators
    Dim gbConfiguredForDA                        ' Is this machine configured for Direct Access?
    Dim goLocalWin32CS                           ' win32_computersystem WMI object for local machine 
    Dim goLocalWin32OS                           ' win32_computersystem WMI object for remote machine
    Dim gbOverride                               ' If newer OS version than tested but assuming Windows 8 behaviour

    ' Latest Version information (if can obtain)
    Dim gszLV_Version                            ' Latest version number  major.minor
    Dim gszLV_Date                               ' Latest version release date
    Dim gszLV_URL                                ' Download URL for latest version
    Dim gszLV_BlogURL                            ' More informati
    Dim gszLV_Type                               ' As in development/pre-release/final
    Dim gszLV_About                              ' Changes in the latest version

    ' Initialise our globals
    glInstalledOS                      = HVREMOTE_INSTALLED_OS_SERVER
    glDebugLevel                       = DBG_NONE
    gbShowMode                         = False
    gbTestConnectivity                 = False
    gbVersionCheck                     = True
    glClientServerMode                 = HVREMOTE_MODE_UNKNOWN    
    glClientOpAnonDCOMMode             = HVREMOTE_CLIENTOP_ANONDCOM_NONE
    gszServerOpAddOrRemoveUserName     = ""
    gszServerOpAddOrRemoveDomainName   = ""
    glServerOpAddRemoveUser            = HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE
    glServerOpAZManUpdate              = HVREMOTE_SERVEROP_AZMANUPDATE_ON
    glServerOpDCOMPermissions          = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON
    glServerOpNameSpacesToUse          = NAMESPACE_CIMV2 Or NAMESPACE_VIRTUALIZATION   ' Note we only add virtv2 after knowing this is windows 8
    glServerOpFirewallHyperV           = HVREMOTE_SERVEROP_FIREWALL_HYPERV_NONE
    glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_NONE
    glClientOpFirewallDA               = HVREMOTE_CLIENTOP_FIREWALL_DA_NONE
    glClientOpTracing                  = HVREMOTE_CLIENTOP_TRACING_NONE
    glRemoteOSRelease                  = WIN_UNKNOWN
    glOSRelease                        = WIN_UNKNOWN
    gszAuthStoreServiceApplication     = ""
    gbComputerIsWorkgroup              = False  ' Assume domain
    gszLocalComputerName               = ""
    gszLocalComputerDomainName         = ""
    gbIsRoleInstalled                  = False  ' Assume not unless we know otherwise
    gbIsSCVMM                          = False
    gszRoleAssign                      = "Administrator"  
    gszLV_Version                      = ""
    gszLV_Date                         = ""
    gszLV_URL                          = "http://code.msdn.microsoft.com/HVRemote"
    gszLV_BlogURL                      = "http://tinyurl.com/kvov7c"  ' Actual URL just too long!
    'gszLV_BlogURL                     = "http://blogs.technet.com/jhoward/archive/2009/08/07/hvremote-refresh.aspx"
    'gszLV_BlogURL                     = "http://blogs.technet.com/jhoward/archive/2008/11/14/configure-hyper-v-remote-management-in-seconds.aspx"
    glElevated                         = ELEVATION_UNKNOWN
    gbIsFirewallRunning                = False
    glWarns                            = 0
    gszWarns                           = ""
    gszRemoteComputerName              = ""
    set goRemoteCIMv2                  = Nothing
    set goRemoteWin32CS                = Nothing
    set goRemoteWin32OS                = Nothing
    set goRemoteVirtualization         = Nothing
    set goRemoteVirtualizationV2       = Nothing
    glRemoteInstalledOS                = HVREMOTE_INSTALLED_OS_UNKNOWN
    gbAnonDCOMAllowed                  = False
    glTestsPassed                      = 0
    gbExplicitAddRemove                = False
    gbConfiguredForDA                  = False
    set goLocalWin32CS                 = Nothing
    set goLocalWin32OS                 = Nothing
    gbOverride                         = False

    
    ' Local Declarations
    Dim oWbemServicesCIMv2                                    ' Connections to WMI namespaces: Cimv2 for all releases
    Dim oWbemServicesVirtualization                           ' Connections to WMI namespaces: Virtualization for 2008 & 2008 R2
    Dim oWbemServicesVirtualizationv2                         ' Connections to WMI namespaces: Virtualizationv2 for Windows 8/2012   
    Dim oWin32SDCIMv2                                         ' Security Descriptor (Win32_SecurityDescriptor) for namespaces
    Dim oWin32SDVirtualization                                ' Security Descriptor (Win32_SecurityDescriptor) for namespaces
    Dim oWin32SDVirtualizationv2                              ' Security Descriptor (Win32_SecurityDescriptor) for namespaces
    Dim lReturn                                               ' Function Return Value
    Dim oTrustee                                              ' Win32_Trustee object being added/removed from DACL
    Dim oHVAdminsTrustee                                      ' Win32_Trustee object for Hyper-V Administrators group SID
    Dim szDCOMUsersGroupName                                  ' Localised
    Dim szHyperVAdminsGroupName                               ' Localised
    Dim bAnonHasAccess                                        ' Does Anonymous Logon have remote access?
    Dim oMachineAccessSD                                      ' Security descriptor for DCOM Remote access (client)
    Dim oMachineLaunchSD                                      ' Security descriptor for DCOM Remote access (server)
    Dim oAuthStore                                            ' AZMan Authorization store
    Dim bBothComputersAreInSameDomain                         ' Hopefully obvious
    Dim szUnused                                              ' As it says

    lReturn                           = NO_ERROR
    set oWbemServicesCIMv2            = Nothing
    set oWbemServicesVirtualization   = Nothing
    set oWbemServicesVirtualizationv2 = Nothing
    set oWin32SDCIMv2                 = Nothing
    set oWin32SDVirtualization        = Nothing
    set oWin32SDVirtualizationv2      = Nothing
    set oTrustee                      = Nothing
    set oHVAdminsTrustee              = Nothing
    szDComUsersGroupName              = ""
    szHyperVAdminsGroupName           = ""
    bAnonHasAccess                    = False
    set oMachineAccessSD              = Nothing
    set oMachineLaunchSD              = Nothing
    set oAuthStore                    = Nothing
    bBothComputersAreInSameDomain     = False    ' Until proven otherwise


    ' Do this with no validation up front to make sure debugging is on from the get go
    if (wscript.arguments.named.exists("debug")) then
        select case wscript.arguments.named("debug")
            case "standard"   glDebugLevel = DBG_STD
            case "verbose"    glDebugLevel = DBG_EXTRA
        end select
    end if

    ' Check this is being launched by cscript
    if instr(lcase(wscript.fullname), "wscript") Then
        MsgBox "Use " & chr(34) & "cscript hvremote.wsf ..." & chr(34) & " to run this script." & vbcrlf & vbcrlf & _
               "You can optionally set the default engine to cscript using " & vbcrlf & _
                chr(34) & "cscript //h:cscript" & chr(34) & ". You would then only need to enter " & vbcrlf & _
               chr(34) & "HVRemote [/mode:client|server] Operations [options]" & chr(34) & ")." & vbcrlf & vbcrlf & _
               "HVRemote must be run from an elevated command prompt for most operations", vbCritical, "HVRemote: Incorrect scripting engine"
        wscript.quit
    end if

    Title ' Display a title about us

    ' We need a CIMv2 namespace connection for just about everything. Connect regardless as just about the first thing we do.
    if (NO_ERROR = lReturn) Then
        Dbg DBG_EXTRA, "Need to connect to cimv2 namespace"
        lReturn = ConnectNameSpace("root\cimv2","", oWbemServicesCIMv2, False)
        if (lReturn) or (oWbemServicesCIMv2 is Nothing) Then
            Error "Giving up as could not connect to root\cimv2 namespace"
            lReturn = -1  
            wscript.quit
        end if
    end if

    ' Some initial output and determining how local machine is configured
    if (NO_ERROR = lReturn) Then

       ' We need the WMI objects for the local computer and operating system.
        Dbg DBG_EXTRA, "Getting WMI objects for CS and OS"
        Call GetLocalWin32CSAndOS(oWbemServicesCIMv2) ' Function will quit if fails

        gszLocalComputerName = lcase(goLocalWin32CS.Name)
        wscript.echo "INFO: Computername is " & gszLocalComputerName

        if Not IsNull(goLocalWin32CS.Workgroup) Then 
            gbComputerIsWorkgroup = True
            wscript.echo "INFO: Computer is in workgroup " & goLocalWin32CS.Workgroup
        else
            gbComputerIsWorkgroup = False
            wscript.echo "INFO: Computer is in domain " & goLocalWin32CS.Domain
            gszLocalComputerDomainName = lcase(goLocalWin32CS.domain)
        end if

        wscript.echo "INFO: Current user is " & replace(goLocalWin32CS.UserName,"\\","\")

        ' Is the Hyper-V Role installed? (So that we can default to assuming server mode, at least for pre-Windows 8)
        gbIsRoleInstalled = TestService(oWbemServicesCIMv2,"VMMS", SERVICE_TEST_PRESENT)

        ' Is the SCVMM Agent installed? 1.03 Using generic function. Also service name is SCVMMAgent in SCVMM 2012.
        gbIsSCVMM = ( (True = TestService(oWbemServicesCIMv2,"VMMAgent", SERVICE_TEST_PRESENT)) or _
                      (True = TestService(oWbemServicesCIMv2,"SCVMMAgent", SERVICE_TEST_PRESENT)) ) 

        wscript.echo "INFO: OS is " & goLocalWin32OS.Version & " " & goLocalWin32OS.OSArchitecture & " " & goLocalWin32OS.Caption

        ' Determine if this is a client. Initialised to default of HVREMOTE_INSTALLED_OS_SERVER
        if goLocalWin32OS.ProductType = 1 Then glInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT

        Call CheckOSVersion() ' Sets glOSRelease. Function will quit if fails.

        if (WIN_6 = glOSRelease) Then Dbg DBG_STD, "Detected Windows Vista/Windows Server 2008 OS"
        if (WIN_7 = glOSRelease) Then Dbg DBG_STD, "Detected Windows 7/Windows Server 2008 R2 OS"
        if (WIN_8 = glOSRelease) Then Dbg DBG_STD, "Detected Windows 8/Windows Server 2012 OS"
        if (WIN_8POINT1 = glOSRelease) Then Dbg DBG_STD, "Detected Windows 8.1/Windows Server 2012 R2 OS"

        ' Use the v2 namespace on server side for Windows 8/2012 
        if (glOSRelease >= WIN_8) Then glServerOpNameSpacesToUse = glServerOpNameSpacesToUse Or NAMESPACE_VIRTUALIZATIONV2

        ' 1.07. With the caveat to above that the Virtualization v1 Namespace is not applicable for Windows 8.1 or later
        if (glOSRelease >= WIN_8POINT1) Then glServerOpNameSpacesToUse = (glServerOpNameSpacesToUse AND (NAMESPACE_CIMV2 OR NAMESPACE_VIRTUALIZATIONV2))
       
        CheckElevation                         ' Works out if we are elevated in glElevated
   
        ParseCommandLine                       ' Work out what we're being asked to do

        ' Do this check AFTER ParseCommandLine. If WIN_LATER and no /override specified, bail out
        ' 1.07 Assume Windows 8.1 (latest release)
        if (WIN_LATER = glOSRelease) then
            if (gbOverride) Then
                glOSRelease = WIN_8POINT1
                wscript.echo "WARN: User override to assume Windows 8.1/Windows Server 2012 R2 behaviour"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Running on a later OS than tested on. User override given" & vbcrlf
            else
                Error ""
                Error "ERROR: This OS release is unsupported. Use the /override parameter to"
                Error "       force HVRemote to assume Windows 8.1/Windows Server 2012 R2 behaviour."
                Error "       This may fail and have unintended side effects."
                wscript.quit
            end if
        end if
        
        ' If Windows 8.1 or later, AZMan is deprecated. Turn this off too.
        if (glOSRelease >= WIN_8POINT1) Then glServerOpAZManUpdate = HVREMOTE_SERVEROP_AZMANUPDATE_OFF

    end if

    ' If server, make sure it has the role installed
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) and _
       (not gbIsRoleInstalled) Then
        Error "Giving up as this does not appear to be a server with Hyper-V running"
        lReturn = -1
    end if

    ' If server, need to be elevated
    if (NO_ERROR = lReturn) and (glClientServerMode = HVREMOTE_MODE_SERVER) and (glElevated = ELEVATION_NO) Then
        wscript.echo ""
        Error ""
        Error "Must run from an elevated command prompt for all server operations"
        Error ""
        lReturn = -1
    end if

    ' If client and not in /show or /trace then need to be elevated (Change 0.7 add trace)
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) and _
       (glElevated = ELEVATION_NO) and _
       (not gbShowMode) and _
       (glClientOpTracing = HVREMOTE_CLIENTOP_TRACING_NONE) Then
        wscript.echo ""
        Error ""
        Error "All client operations which change the configuration must be run"
        Error "from an elevated command prompt."
        Error ""
        lReturn = -1
    end if

    ' If server, make sure it is not being managed by SCVMM
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) and _
       (gbIsSCVMM) Then
        wscript.echo " "
        Error " "
        Error "Quitting - This server appears to be managed by System Center"
        Error "           Virtual Machine Manager. See documentation."
        Error " "
        lReturn = -1
    end if

    ' 1.03 The /explicit option is only available on Windows 8/Windows Server 2012 and later
    if (NO_ERROR = lReturn) then
        if ((glClientServerMode = HVREMOTE_MODE_SERVER) and _
            (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _           
            (gbExplicitAddRemove) And _
            (glOSRelease < WIN_8)) Then
            Usage "ERROR: /explicit is only available on Windows 8/Windows Server 2012 and later"
            wscript.quit
        end if 
    end if

    ' If in show mode and testing connectivity in either direction, try to get info about      
    ' the remote machine. This sets three global objects: goRemoteWin32CS, goRemoteWin32OS & goRemoteCIMv2.
    ' If this machine is a client, it also sets goRemoteVirtualization (Windows 8 only, deprecated in Windows 8.1).
    ' If this machine is a client and remote is Server 2012+, also sets goRemoteVirtualizationV2
    ' It also sets the global glRemoteOSRelease. Also moved this up front
    if (NO_ERROR = lReturn) and (gbShowMode) and (gbTestConnectivity) Then
        Dbg DBG_STD, "Getting information about remote machine"
        lReturn = GetRemoteMachineInfo()
        if lReturn then
            lReturn = NO_ERROR
            Dbg DBG_STD, "Failed to get remote machine info. Silently continuing"
        end if
    end if
    
    ' Is the Windows Firewall running? 0.7 Moved this later. Must be after we know what operating system is running
    if (NO_ERROR = lReturn) Then
        gbIsFirewallRunning = IsFirewallRunning(oWbemServicesCIMv2)
    end if

    ' If Windows Server 2008 SP1, check QFE is present for RTM update to Hyper-V
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) and _
       (WIN_6 = glOSRelease) and _
       (goLocalWin32OS.ServicePackMajorVersion = 1) Then
        if IsQFEInstalled(oWbemServicesCIMv2, "950050") then
            wscript.echo "INFO: This machine has the Hyper-V (v1) QFE installed (KB950050)"
        else
            Error "Giving up as this server is running Hyper-V pre-release code."
            Error "Install KB950050 from http://support.microsoft.com/kb/950050"
            wscript.quit
        end if
    end if

    ' 1.03 Is Direct Access configured? Note DA can be on server as well. Windows 7 onwards. 
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) Then
        gbConfiguredForDA = IsMachineConfiguredForDA(oWbemServicesCIMv2)
        if (gbConfiguredForDA) Then wscript.echo "INFO: This computer is configured for Direct Access"
    end if

    ' Do client checks for SKUs and QFEs 
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) Then
        lReturn = DoClientChecks(oWbemServicesCIMv2)
    end if

    ' Client side. Check tracing (New 0.7)
    if (NO_ERROR = lReturn) And _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
       (gbShowMode) Then
        Call CheckTracing()
    end if

    ' Connect to root\virtualization namespace
    if (NO_ERROR = lReturn) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATION)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Need to connect to virtualization namespace"
        lReturn = ConnectNameSpace("root\virtualization", "", oWbemServicesVirtualization, False)
        if (lReturn) or (oWbemServicesVirtualization is Nothing) Then
            Error "Giving up as could not connect to root\virtualization namespace"
            Error "You could try /debug or limiting the namespaces using the /ns option "
            Error "but remote management won't work unless this namespace security is set"
            lReturn = -1  
        end if
    end if

    ' Connect to root\virtualization\v2 namespace if Windows 8 or Later
    if (NO_ERROR = lReturn) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATIONV2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (glOSRelease >= WIN_8) Then
        Dbg DBG_EXTRA, "Need to connect to virtualization\v2 namespace"
        lReturn = ConnectNameSpace("root\virtualization\v2", "", oWbemServicesVirtualizationv2, False)
        if (lReturn) or (oWbemServicesVirtualizationv2 is Nothing) Then
            Error "Giving up as could not connect to root\virtualization\v2 namespace"
            Error "You could try /debug or limiting the namespaces using the /ns option "
            Error "but remote management won't work unless this namespace security is set"
            lReturn = -1  
        end if
    end if

    ' Get the current security descriptor for the cimv2 namespace
    if (NO_ERROR = lReturn) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Need to get the security desciptor for the CIMv2 namespace"
        lReturn = GetWin32SD (oWbemServicesCIMv2, oWin32SDCIMv2)
        if (lReturn) or (oWin32SDCIMv2 is nothing) Then
            lReturn = -1
            Error "Giving up as not able to get the security descriptor for the cimv2 namespace"
            Error "Are you running as an admin from an *ELEVATED* prompt???"
        end if     
    end if 

    ' Get the current security descriptor for the virtualization namespace
    if (NO_ERROR = lReturn) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATION)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Need to get the security desciptor for the virtualization namespace"
        lReturn = GetWin32SD (oWbemServicesVirtualization, oWin32SDVirtualization)
        if (lReturn) or (oWin32SDVirtualization is nothing) Then
            lReturn = -1
            Error "Giving up as not able to get the security descriptor for the virtualization namespace"
            Error "Are you running as an admin from an *ELEVATED* prompt???"
        end if     
    end if 

    ' Get the current security descriptor for the virtualization\v2 namespace for Windows 8
    if (NO_ERROR = lReturn) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATIONV2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (glOSRelease >= WIN_8) Then
        Dbg DBG_EXTRA, "Need to get the security desciptor for the virtualization\v2 namespace"
        lReturn = GetWin32SD (oWbemServicesVirtualizationv2, oWin32SDVirtualizationv2)
        if (lReturn) or (oWin32SDVirtualizationv2 is nothing) Then
            lReturn = -1
            Error "Giving up as not able to get the security descriptor for the virtualization\v2 namespace"
            Error "Are you running as an admin from an *ELEVATED* prompt???"
        end if     
    end if 

    ' Display the Security Descriptor for CIMv2 Namespace
    if (NO_ERROR = lReturn) and _
       (gbShowMode) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Showing the cimv2 namespace SD"
        DisplayWin32SD "root\cimv2", 1, oWin32SDCimv2
    end if

    ' Display the Security Descriptor for Virtualization Namespace
    if (NO_ERROR = lReturn) and _
       (gbShowMode) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATION)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Showing the virtualization namespace SD"
        DisplayWin32SD "root\virtualization", 1, oWin32SDVirtualization
        if (lReturn) Then Error "Giving up as could not display the virtualization namespace security descriptor"
    end if

    ' Display the Security Descriptor for Virtualization\v2 Namespace for Windows 8 and Later
    ' Oops this was a bug in 1.06 - the condition was incorrectly using VIRTUALIZATION, not VIRTUALIZATIONV2
    if (NO_ERROR = lReturn) and _
       (gbShowMode) And _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATIONV2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
       (glOSRelease >= WIN_8) Then
        Dbg DBG_EXTRA, "Showing the virtualization\v2 namespace SD"
        DisplayWin32SD "root\virtualization\v2", 1, oWin32SDVirtualizationv2
        if (lReturn) Then Error "Giving up as could not display the virtualization\v2 namespace security descriptor"
    end if

    ' Open the authorization policy store
    ' 1.07 This is present in Windows 8.1 but does nothing. For this, glServerOpAZManUpdate is not set, so not opened or shown
    if (NO_ERROR = lReturn) and _
       (glServerOpAZManUpdate = HVREMOTE_SERVEROP_AZMANUPDATE_ON) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Opening the AZMan policy store"
        lReturn = OpenAuthorizationStore(oAuthStore)
        if lReturn Then
            Error "Giving up as could not open the authorization store"
        end if
    end if ' Open the authorization policy store

    ' Display the Authorization Store
    if (NO_ERROR = lReturn) and _
       (gbShowMode) and _
       (glServerOpAZManUpdate = HVREMOTE_SERVEROP_AZMANUPDATE_ON) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        lReturn = DisplayAuthorizationStore(oAuthStore, gszRoleAssign)
        if lReturn Then Error "Giving up as could not display the authorization store"
    end if ' Display the Authorization Store


    ' Get the localized group name for the "Distributed COM Users" group
    if (NO_ERROR = lReturn) And _
       (glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) Then
        Dbg DBG_EXTRA, "Getting localized group name for Distributed COM Users"
        lReturn = GetGroupNameForSID (SID_DISTRIBUTED_COM_USERS, szDCOMUsersGroupName)
        Dbg DBG_STD, "Distributed COM Users group name (localised) is '" & szDCOMUsersGroupName & "'"
    end if

    ' Get the localized group name for the "Hyper-V Administrators" group if Windows 8 or Later
    if (NO_ERROR = lReturn) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (glOSRelease >= WIN_8) Then
        Dbg DBG_EXTRA, "Getting localized group name for Hyper-V Administrators"
        lReturn = GetGroupNameForSID (SID_HYPERV_ADMINISTRATORS, szHyperVAdminsGroupName)
        Dbg DBG_STD, "Hyper-V Administrators group name (localised) is '" & szHyperVAdminsGroupName & "'"
    end if

    ' Enumerate the Distributed COM Users Group  (Need to be done after have CIMv2 namespace object)
    if (NO_ERROR = lReturn) and _
       (glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON) and _
       (gbShowMode) and _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) Then
        Dbg DBG_EXTRA, "Showing the contents of the Distributed COM Users Group"
        lReturn = EnumerateGroupMembers (szDCOMUsersGroupName, oWbemServicesCIMv2)
    end if

    ' 1.03 Enumerate the Hyper-V Administrators Group (Need to be done after have CIMv2 namespace object)
    if (NO_ERROR = lReturn) and _
       (gbShowMode) and _
       (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
       (glOSRelease >= WIN_8) Then
        Dbg DBG_EXTRA, "Showing the contents of the Hyper-V Administrators Group"
        lReturn = EnumerateGroupMembers (szHyperVAdminsGroupName, oWbemServicesCIMv2)
    end if

    ' New for 0.3 Not just Distributed COM as it could be available through direct SD capability
    ' in the Machine Launch DCOM security permissions. Change in 1.03. Have updated the conditions
    ' slightly here so that we always get the SD as needed for updating on client Hyper-V in Windows 8.
    ' But still only show the SD under the same conditions.
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) Then
        Dbg DBG_EXTRA, "Getting the machine Launch Restrictions"
        lReturn = GetMachineRestrictionSDFromRegistry (MACHINE_LAUNCH_RESTRICTION_KEY, oMachineLaunchSD)
        if (NO_ERROR = lReturn) Then
            if (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) and _
               (glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON) and _
               (gbShowMode) Then
                DisplayWin32SD "COM Security Launch and Activation Permissions", 2, oMachineLaunchSD
            end if
        else
            Error "Giving up as failed to get machine launch restriction"
        end if
    end if

    ' If we are adding or removing a user, then we need a Win32_Trustee object for DACL updates. Trustee is part of the ACE.
    if (NO_ERROR = lReturn) and _
       (glServerOpAddRemoveUser<>HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) Then
        Dbg DBG_EXTRA, "Have an add or remove - need the trustee objet"
        lReturn = GetTrustee(gszServerOpAddOrRemoveDomainName, gszServerOpAddOrRemoveUserName, oTrustee)
    end if


    ' Add User or group to root\cimv2 namespace permissions
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease >= WIN_8) and (gbExplicitAddRemove)) ) Then

        wscript.echo ""
        wscript.echo "Adding user or group to root\cimv2 namespace..."
        lReturn = AddACEToDACL(oWin32SDCimv2, oWbemServicesCIMv2, oTrustee, True)
        select case lReturn
            case ERROR_ALREADY_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                 ' wscript.echo "INFO: DACL with user or group ACE built"
                 lReturn = SetWin32SD("root\cimv2", oWin32SDCimv2, oWBemServicesCIMv2)
                 if lReturn Then
                    wscript.echo "Giving up due to error setting security permissions on root\cimv2"
                 else
                    wscript.echo "INFO: root\cimv2 namespace permissions updated OK"
                 end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\cimv2 namespace)"
         end select
    End If

    ' Remove User or group from root\cimv2 namespace permissions
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_CIMv2)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease >= WIN_8) and (gbExplicitAddRemove)) ) Then

        wscript.echo ""
        wscript.echo "Removing user or group from root\cimv2 namespace..."
        lReturn = RemoveACEFromDACL(oWin32SDCimv2, oWbemServicesCIMv2, oTrustee)
        select case lReturn
            case ERROR_NOT_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                wscript.echo "INFO: DACL without user or group ACE in it built"
                lReturn = SetWin32SD("root\cimv2", oWin32SDCimv2, oWBemServicesCIMv2)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\cimv2"
                   else
                       wscript.echo "INFO: root\cimv2 namespace permissions updated OK"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\cimv2 namespace)"
         end select
    End If

    ' Add User or group to root\virtualization namespace permissions
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATION)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease = WIN_8) and (gbExplicitAddRemove)) ) Then

        wscript.echo ""
        wscript.echo "Adding user or group to root\virtualization namespace..."
        ' NO - this is not a typo below. It does need the CIMV2 namespace connection
        lReturn = AddACEToDACL(oWin32SDVirtualization, oWbemServicesCIMv2, oTrustee,True)

        select case lReturn
            case ERROR_ALREADY_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                'wscript.echo "INFO: DACL with user or group ACE built"
                lReturn = SetWin32SD("root\virtualization", oWin32SDVirtualization, oWBemServicesVirtualization)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\virtualization"
                   else
                       wscript.echo "INFO: root\virtualization namespace permissions updated OK"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\virtualization namespace)"
         end select
    End If

    ' Add User or group to root\virtualization\v2 namespace permissions
    ' 1.07 For Windows 8.1 and later. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATIONV2)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
          ((glOSRelease >= WIN_8POINT1) and (gbExplicitAddRemove)) ) Then

        wscript.echo ""
        wscript.echo "Adding user or group to root\virtualization\v2 namespace..."
        ' NO - this is not a typo below. It does need the CIMV2 namespace connection
        lReturn = AddACEToDACL(oWin32SDVirtualizationv2, oWbemServicesCIMv2, oTrustee,True)

        select case lReturn
            case ERROR_ALREADY_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                'wscript.echo "INFO: DACL with user or group ACE built"
                lReturn = SetWin32SD("root\virtualization\v2", oWin32SDVirtualizationv2, oWBemServicesVirtualizationv2)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\virtualization\v2"
                   else
                       wscript.echo "INFO: root\virtualization\v2 namespace permissions updated OK"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\virtualization\v2 namespace)"
         end select
    End If


    ' Remove User or group from root\virtualization namespace permissions
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATION)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease = WIN_8) and (gbExplicitAddRemove)) ) Then
        wscript.echo ""
        wscript.echo "Removing user or group from root\virtualization namespace..."
        ' NO - this is not a typo below. It does need the CIMV2 namespace connection
        lReturn = RemoveACEFromDACL(oWin32SDVirtualization, oWbemServicesCIMv2, oTrustee)

        select case lReturn
            case ERROR_NOT_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                wscript.echo "INFO: DACL without user or group ACE in it built"
               ' NO - this is not a typo below. It does need the CIMV2 namespace connection
                lReturn = SetWin32SD("root\virtualization", oWin32SDVirtualization, oWBemServicesVirtualization)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\virtualization"
                   else
                       wscript.echo "INFO: root\virtualization namespace permissions updated OK"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\virtualization namespace)"
         end select
    End If

    ' Remove User or group from root\virtualization namespace permissions
    ' 1.07 For Windows 8.1 and later. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) And _
          (0<>(glServerOpNameSpacesToUse And NAMESPACE_VIRTUALIZATIONV2)) And _
          (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
          ((glOSRelease >= WIN_8POINT1) and (gbExplicitAddRemove)) ) Then


        wscript.echo ""
        wscript.echo "Removing user or group from root\virtualization\v2 namespace..."
        ' NO - this is not a typo below. It does need the CIMV2 namespace connection
        lReturn = RemoveACEFromDACL(oWin32SDVirtualizationv2, oWbemServicesCIMv2, oTrustee)

        select case lReturn
            case ERROR_NOT_PRESENT
                 wscript.echo "INFO: No action taken here"
                 lReturn = NO_ERROR
            case NO_ERROR
                wscript.echo "INFO: DACL without user or group ACE in it built"
               ' NO - this is not a typo below. It does need the CIMV2 namespace connection
                lReturn = SetWin32SD("root\virtualization\v2", oWin32SDVirtualizationv2, oWBemServicesVirtualizationv2)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\virtualization\v2"
                   else
                       wscript.echo "INFO: root\virtualization\v2 namespace permissions updated OK"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\virtualization\v2 namespace)"
         end select
    End If


    ' Add User or group to Distributed COM Users
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser   = HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
          (glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON) And _
          (glClientServerMode        = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease >= WIN_8) and (gbExplicitAddRemove)) ) Then
        Dbg DBG_EXTRA, "Adding user to DCOM Users group"
        lReturn = AddUserToGroup(gszServerOpAddOrRemoveDomainName, gszServerOpAddOrRemoveUserName, szDCOMUsersGroupName)
    End If

    ' Remove User or group from Distributed COM Users
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser   = HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) And _
          (glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_ON) And _
          (glClientServerMode        = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease >= WIN_8) and (gbExplicitAddRemove)) ) Then

        Dbg DBG_EXTRA, "Removing user from DCOM Users Group"
        lReturn = RemoveUserFromGroup(gszServerOpAddOrRemoveDomainName, gszServerOpAddOrRemoveUserName, szDCOMUsersGroupName)
    End If

    ' Add or remove user to authorization store
    ' 1.03 For Windows 8, change logic. Only do this if explicitly asked, but always do downlevel
    ' 1.07 Changed to only for Win8 as AZMan deprecated. Not strictily needed as 8.1 as we already turn of glServerOpAZManUpdate
    if (NO_ERROR = lReturn) and _
       (  (glServerOpAddRemoveUser   <>HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) And _
          (glServerOpAZManUpdate     = HVREMOTE_SERVEROP_AZMANUPDATE_ON) And _
          (glClientServerMode        = HVREMOTE_MODE_SERVER ) ) And _
       (  (glOSRelease < WIN_8) Or _
          ((glOSRelease = WIN_8) and (gbExplicitAddRemove)) ) Then

        lReturn = AddRemoveAuthorizationStore(oAuthSTore, gszRoleAssign)
    end if

    ' Add User or group to Hyper-V Administrators group (Windows 8 default action)
    if (NO_ERROR = lReturn) and _
       (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
       (glOSRelease >= WIN_8) And _
       (not gbExplicitAddRemove) Then
        Dbg DBG_EXTRA, "Adding user to Hyper-V Administrators group"
        lReturn = AddUserToGroup(gszServerOpAddOrRemoveDomainName, gszServerOpAddOrRemoveUserName, szHyperVAdminsGroupName)
    End If

    ' Remove User or group from Hyper-V Administrators group (Windows 8 default action)
    if (NO_ERROR = lReturn) and _
       (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
       (glOSRelease >= WIN_8) And _
       (not gbExplicitAddRemove) Then
        Dbg DBG_EXTRA, "Removing user from Hyper-V Administrators Group"
        lReturn = RemoveUserFromGroup(gszServerOpAddOrRemoveDomainName, gszServerOpAddOrRemoveUserName, szHyperVAdminsGroupName)
    End If


    ' 1.03 Server side. Get a trustee object for the Hyper-V Administators SID as we may need to fix the bits missing
    ' in setup on Client Hyper-V in Windows 8
    if (NO_ERROR = lReturn) and _
       (glOSRelease >= WIN_8) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) and _
       (glInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT) THen
        ' We need a trustee object for the Hyper-V Administrators group
        lReturn = GetTrusteeForSID (SID_HYPERV_ADMINISTRATORS, oHVAdminsTrustee)
        if (lReturn) Then
            Error "FAILED: Could not get Trustee for " & SID_HYPERV_ADMINISTRATORS
            lReturn = -1
        end if
    end if

    ' 1.03 Server side. As setup is incorrect, add Hyper-V Administrators to the CIMv2 namespace explicitly if not already there
    if (NO_ERROR = lReturn) and _
       (glOSRelease >= WIN_8) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) and _
       (glInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT) THen

        lReturn = AddACEToDACL(oWin32SDCIMv2, oWbemServicesCIMv2, oHVAdminsTrustee,False)

        select case lReturn
            case ERROR_ALREADY_PRESENT
                 'wscript.echo "INFO: Hyper-V Administrators already has access to CIMv2 namespace"
                 lReturn = NO_ERROR
            case NO_ERROR
                'wscript.echo "INFO: DACL with user or group ACE built"
                lReturn = SetWin32SD("root\cimv2", oWin32SDCIMv2, oWBemServicesCIMv2)
                   if lReturn Then
                       wscript.echo "Giving up due to error setting security permissions on root\cimv2"
                   else
                       wscript.echo "INFO: Granted Hyper-V Administrators access to root\cimv2"
                   end if
            case else
                 wscript.echo "Giving up due to some other error (updating root\cimv2 namespace)"
         end select
    end if

    ' 1.03 Server side. As setup is incorrect on Windows 8 client running Hyper-V, add Hyper-V Administrators 
    ' to local/remote activation/launch permissions in COM if not already there
    ' 1.07 Note - this also applies to Windows 8.1
    if (NO_ERROR = lReturn) and _
       (glOSRelease >= WIN_8) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (glInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT) Then
        Dbg DBG_EXTRA, "Adding Hyper-V Administators group to COM Machine Launch SD if missing"
        lReturn = AddHyperVAdminsInMachineLaunchSDIfMissing(oWbemServicesCIMv2, oMachineLaunchSD)
     end if


    ' Client side. Add/Remove Anonymous logon to remote DCOM access. First need existing SD
    if (NO_ERROR                =  lReturn) And _
       (glClientServerMode      =  HVREMOTE_MODE_CLIENT) and _
       (glClientOpAnonDCOMMode  <> HVREMOTE_CLIENTOP_ANONDCOM_NONE) Then

        wscript.echo ""
        wscript.echo "INFO: Obtaining current Machine Access Restriction..."  
        lReturn = GetMachineRestrictionSDFromRegistry(MACHINE_ACCESS_RESTRICTION_KEY, oMachineAccessSD)
        if lReturn Then
            wscript.echo "Giving up as unable to obtain machine access restriction security descriptor"
        end if
     end if

    ' Client side. Add Anonymous logon to remote DCOM access. First need existing SD
    if (NO_ERROR                = lReturn) And _
       (glClientServerMode      = HVREMOTE_MODE_CLIENT) and _
       (glClientOpAnonDCOMMode  = HVREMOTE_CLIENTOP_ANONDCOM_GRANT) Then
        wscript.echo "INFO: Examining security descriptor"        
        bAnonHasAccess = DoesAnonymousLogonHaveRemoteDCOM(oMachineAccessSD)
        if bAnonHasAccess then
            wscript.echo "INFO: Nothing to do - ANONYMOUS LOGON already has remote access"
        else
            lReturn = AddAnonymousLogonToRemoteDCOM (oWbemServicesCIMv2, oMachineAccessSD)
            if (lReturn) Then
                wscript.echo "Giving up as unable to add anonymous logon to DCOM remote access permission"
            end if
   
        end if
    End if

    ' Client side. Remove Anonymous logon from remote DCOM access. First need existing SD
    if (NO_ERROR                =  lReturn) And _
       (glClientServerMode      =  HVREMOTE_MODE_CLIENT) and _
       (glClientOpAnonDCOMMode  =  HVREMOTE_CLIENTOP_ANONDCOM_REVOKE) Then
        wscript.echo "INFO: Examining security descriptor"  
        bAnonHasAccess = DoesAnonymousLogonHaveRemoteDCOM(oMachineAccessSD)
        if not bAnonHasAccess then
            wscript.echo "INFO: Nothing to do - ANONYMOUS LOGON does not have remote access"
        else
            lReturn = RemoveAnonymousLogonFromRemoteDCOM (oMachineAccessSD)
            if (lReturn) Then
                wscript.echo "Giving up as unable to remove anonymous logon from DCOM remote access permission"
            end if
   
        end if
     End if

     ' Client checks for compatibility between the client the server. We must have remote machine info 
     ' to do this. This also sets bBothComputersAreInSameDomain if that is the case.
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (gbShowMode) and _
        (gbTestConnectivity) and _
        (not goRemoteWin32CS is nothing) and _
        (not goRemoteWin32OS is nothing) and _
        (not goRemoteCIMv2 is nothing) Then

         Dbg DBG_STD, "Checking for client compatibility to server"
   
         ' Only do domain check if target and client are both known to be domain joined
         if NO_ERROR = lReturn and _
            (goRemoteWin32CS.PartOfDomain) and _
            (not gbComputerIsWorkgroup) and _
            (len(gszLocalComputerDomainName) > 0) and _
            (lcase(gszLocalComputerDomainName) = lcase(goRemoteWin32CS.Domain)) then
            Dbg DBG_EXTRA, "Both computers are in the same domain"
            bBothComputersAreInSameDomain = True
         end if


         ' Downlevel check. This is not supported
         ' WIN_7 here and targetting pre-vista, or pre-6.1 (which effectively means 2008)    OR
         ' WIN_8 here and targetting pre-vista, or pre-6.2 (ie 2008 or 2008 R2)

         if (NO_ERROR = lReturn) and (glRemoteOSRelease > glOSRelease) Then         
             glWarns = glWarns + 1
             gszWarns = gszWarns & glWarns & ": You are attempting to connect to a newer version of Hyper-V. " & vbcrlf & _
                                             "  While some remote management *may* be possible, you should use a " & vbcrlf & _
                                             "  matching operating system version on the client for full " & vbcrlf & _
                                             "  management capabilities." & vbcrlf
         end if

         ' Downlevel check. This is not recommended.                 _
         if (NO_ERROR = lReturn) and (glRemoteOSRelease < glOSRelease) Then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": You are attempting to connect to an older version of Hyper-V. " & vbcrlf 

                ' This is true for Windows 8, but not Windows 8.1. Hence = in condition, not >= !!
                if glOSRelease = WIN_8 then gszWarns = gszWarns & "   Windows Server 2012/Windows 8 Hyper-V Manager cannot " & vbcrlf & _
                                                                   "   connect to a downlevel server. Only WMI calls will be possible." & vbcrlf
         end if

     end if


     ' Client side. Show anonymous dcom access setting. Note that part of this block of code also
     ' needs to know if both computers are in the same domain, so must be AFTER that is set (in block above)
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (gbShowMode) Then
        lReturn = GetMachineRestrictionSDFromRegistry(MACHINE_ACCESS_RESTRICTION_KEY, oMachineAccessSD)

        if NO_ERROR = lReturn Then 
            Call DisplayWin32SD ("COM Security Access Permissions", 2, oMachineAccessSD)
            wscript.echo " "
            wscript.echo "-------------------------------------------------------------------------------"
            wscript.echo "ANONYMOUS LOGON Machine DCOM Access"
            wscript.echo "-------------------------------------------------------------------------------"
            wscript.echo " "

            if DoesAnonymousLogonHaveRemoteDCOM(oMachineAccessSD) Then

                gbAnonDCOMAllowed = True

                if not(gbComputerIsWorkgroup) then

                    if (bBothComputersAreInSameDomain) Then

                         ' This is not necessary (but depends if this client is also managing 
                         ' machines which are in a workgroup or other domain)
     
                         wscript.echo "WARN: ANONYMOUS LOGON does have remote access"
                         wscript.echo " "
                         wscript.echo "  This setting should only be enabled if required as security on this "
                         wscript.echo "  machine has been lowered. It is needed if you need to manage Hyper-V"
                         wscript.echo "  on a remote server which is either in an an untrusted domain from this"
                         wscript.echo "  machine, or both machines are in a workgroup. However, the target" 
                         wscript.echo "  being tested is in the same domain as this machine."
                         wscript.echo ""

                         wscript.echo ""
                         wscript.echo "  Both computers are in domain " & gszLocalComputerDomainName
                         wscript.echo ""

                         wscript.echo "  Use hvremote /mode:client /anondcom:revoke to turn off if required"
 
                         glWarns = glWarns + 1
                         gszWarns = gszWarns & glWarns & ": Anonymous Logon has remote access (see above for detail)" & vbcrlf
                    else

                         ' Computers are not in the same domain (or workgroups). We need anon dcom enabled which it is.    
                         wscript.echo "ANONYMOUS LOGON has remote access"
                         wscript.echo " "
                         wscript.echo "  Security on this machine has been lowered. It is needed if you "
                         wscript.echo "  need to manage Hyper-V on a remote server which is either in an "
                         wscript.echo "  untrusted domain from this machine, or both machines are in a workgroup."
                         wscript.echo ""
                         wscript.echo "  Use hvremote /mode:client /anondcom:revoke to turn off"
                    end if
                else
                    ' Workgroup - this is required
                    wscript.echo "ANONYMOUS LOGON has remote access"
                end if


            else

                gbAnonDCOMAllowed = False

                ' 0.7 Additional message
                if(gbComputerIsWorkgroup) then
                    wscript.echo "WARN: ANONYMOUS LOGON does not have remote access"
                    wscript.echo " "
                    wscript.echo "  This setting is required when the client is in a workgroup, or the"
                    wscript.echo "  server is in an untrusted domain from the client."
                    wscript.echo ""
                    wscript.echo "  Use hvremote /mode:client /anondcom:grant to turn on"

                    glWarns = glWarns + 1
                    gszWarns = gszWarns & glWarns & ": Anonymous Logon does not have remote access" & vbcrlf

                else

                    wscript.echo "ANONYMOUS LOGON does not have remote access"
                    wscript.echo " "
                    wscript.echo "  This setting should only be enabled if required as security on this "
                    wscript.echo "  machine will be lowered. This computer is in a domain. It is not "
                    wscript.echo "  required if the server(s) being managed are in the same or trusted"
                    wscript.echo "  domains."
                    wscript.echo ""

                    ' 1.03 Fix. Thanks to Greig Sheridan - typo where did say anondcom:enable
                    wscript.echo "  Use hvremote /mode:client /anondcom:grant to turn on if required"

                    if (not(bBothComputersAreInSameDomain)) Then
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Anonymous Logon does not have remote access (may be ok)" & vbcrlf
                    else
                        wscript.echo ""
                        wscript.echo "  Both computers are in domain " & gszLocalComputerDomainName
                        wscript.echo ""
                    end if

                end if
            end if
         end if

      end if

                 
     ' Client side. Show firewall policies?
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (gbShowMode) Then
         lReturn = ShowFirewallPolicyForGroup (HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE, "Hyper-V Management Clients", True, True)
     end if



     ' Client side. Message about cmdkey if going from a domain client to a workgroup server
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        not(gbComputerIsWorkgroup) and _
        (gbShowMode) and _
        (gbTestConnectivity) and _
        (not bBothComputersAreInSameDomain) Then

         if (not goRemoteWin32CS is nothing) Then
             if Not IsNull(goRemoteWin32CS.Workgroup) Then 

                 ' Yup, target is in a workgroup
                 wscript.echo " "
                 wscript.echo "-------------------------------------------------------------------------------"
                 wscript.echo "Additional configuration may be necessary"
                 wscript.echo "-------------------------------------------------------------------------------"
                 wscript.echo " "
                 wscript.echo "  This computer is in a domain. As the target server is in a workgroup, "
                 wscript.echo "  you may need to set credentials for the server for Hyper-V Remote "
                 wscript.echo "  Management to operate correctly."
                 wscript.echo " "
                 wscript.echo "  If necessary, from a *NON* elevated command prompt, enter:"
                 wscript.echo " "
                 wscript.echo "     cmdkey /add:ServerComputerName /user:ServerComputerName\UserName /pass"
                 wscript.echo " "
                 wscript.echo "  Note that you MUST enter ServerComputerName to BOTH parameters."
                 wscript.echo "  You will be prompted for a password after entering the command."
                 wscript.echo " "
                 glWarns = glWarns + 1
                 gszWarns = gszWarns & glWarns & ": You may need to set credentials to access the server (see info above)" & vbcrlf

             end if
         end if
     end if

     ' Client side. Change firewall policies for the HyperVManagementClient?
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (glClientOpFirewallHyperVMgmtClient <> HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_NONE) Then

         lReturn = ChangeFirewallPolicyForGroup ( HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE, _
                                                  (glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_ALLOW))

     end if

     ' Client side. Enable firewall policies for DA? (New 1.03)
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (glClientOpFirewallDA = HVREMOTE_CLIENTOP_FIREWALL_DA_ENABLE) Then
         lReturn = SetDAFirewallRules(True)
     end if

     ' Client side. Disable firewall policies for DA? (New 1.03)
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (glClientOpFirewallDA = HVREMOTE_CLIENTOP_FIREWALL_DA_DISABLE) Then
         lReturn = SetDAFirewallRules(False)
     end if

     ' Client side. Tracing On (New 0.7)
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (glClientOpTracing = HVREMOTE_CLIENTOP_TRACING_ON) Then
         lReturn = ConfigureClientTracingOn()
     end if

     ' Client side. Tracing Off (New 0.7)
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
        (glClientOpTracing = HVREMOTE_CLIENTOP_TRACING_OFF) Then
         lReturn = ConfigureClientTracingOff()
     end if

     ' Server side. Show firewall policies?
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_SERVER) And _
        (gbShowMode) Then
        ' Drop through ignore RC
        if (glOSRelease >= WIN_7)  Then
            Call ShowFirewallPolicyForGroup (HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_WIN7, "Hyper-V", True, True)
        else
            Call ShowFirewallPolicyForGroup (HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_V1, "Hyper-V", True, True)
        end if
     end if

     ' Server side. Change firewall policies for Hyper-V Server-side configuration?
     if (NO_ERROR = lReturn) And _
        (glClientServerMode = HVREMOTE_MODE_SERVER) And _
        (glServerOpFirewallHyperV <> HVREMOTE_SERVEROP_FIREWALL_HYPERV_NONE) Then
        if (WIN_7 = glOSRelease)  Then
            lReturn = ChangeFirewallPolicyForGroup ( HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_WIN7, _
                                                   (glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_ALLOW))
        else
            lReturn = ChangeFirewallPolicyForGroup ( HVREMOTE_SERVEROP_FIREWALL_HYPERV_RESOURCE_v1, _
                                                   (glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_ALLOW))
        end if
     end if

    ' Message about possible restart if adding. This appears to have been fixed in Windows 8.
    if (NO_ERROR = lReturn) and _
       (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) And _
       (glClientServerMode = HVREMOTE_MODE_SERVER ) And _
       (glOSRelease < WIN_8) Then
        wscript.echo ""
        wscript.echo "NOTE: If this is the first time you have used HVRemote " 
        wscript.echo "to add a user for remote configuration, it may be necessary"
        wscript.echo "to restart this machine. See documentation for further "
        wscript.echo "information."
    End If

    ' Server and Client (v0.4) I'm always needing IPConfig output, so easier to just include it
    if (NO_ERROR = lReturn) and (gbShowMode) Then
         lReturn = RunShellCmd("ipconfig /all", "IP Configuration",True,szUnused,False)
    end if

    ' Client side. (v0.4) Are there cmdkey exceptions in place?
    if (NO_ERROR = lReturn) And _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
       (gbShowMode) Then
        lReturn = RunShellCmd("cmdkey /list", "Stored Credentials",True,szUnused,False)
    end if

    ' Client side (v0.7) Test connectivity to a target server?
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
       (gbShowMode) And _
       (gbTestConnectivity) THen
        lReturn = TestCallsToServer(oWbemServicesCIMv2)
        lReturn = NO_ERROR ' Don't worry if fails
    end if

    ' Server side (v0.7) Test connectivity to a target client?
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (gbShowMode) And _
       (gbTestConnectivity) THen
        lReturn = TestCallsToClient(oWbemServicesCIMv2)
        lReturn = NO_ERROR ' Don't worry if fails
    end if

    ' Check for latest version
    if (NO_ERROR = lReturn) and (gbVersionCheck) Then
        lReturn = AmILatestVersion ("http://blogpics.dyndns.org/HVRemote-Latest-Version.txt")
        if lReturn = -2 Then ' Not located - alternate location
            lReturn = AmILatestVersion ("http://blogs.technet.com/jhoward/pages/hvremotelatestversion.aspx")
        end if
        lReturn = NO_ERROR
    End If

    if (glWarns) Then
        wscript.echo ""
        wscript.echo "-------------------------------------------------------------------------------"
        Dim szTemp
        szTemp = glWarns & " warning"
        if glWarns>1 then szTemp = szTemp & "s"
        szTemp = szTemp & " or error"
        if glWarns>1 then 
            szTemp = szTemp & "s were"
        else
            szTemp = szTemp & " was"
        end if
        wscript.echo szTemp & " found in the configuration. Review the "
        wscript.echo "detailed output above to determine whether you need to take further action."
        wscript.echo "Summary is below."
        wscript.echo " "
        wscript.echo gszWarns
        wscript.echo "-------------------------------------------------------------------------------"
    end if

    ' Client side (v0.7) Warning of no connectivity test
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_CLIENT) And _
       (gbShowMode) And _
       (not gbTestConnectivity) THen
        wscript.echo ""
        wscript.echo ""
        wscript.echo ""
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Did you know.... HVRemote can help diagnose common errors?"
        wscript.echo ""
        wscript.echo " Instead of running HVRemote /show, run HVRemote /show /target:servername."
        wscript.echo " This runs a series of tests against the server to verify connectivity."
        wscript.echo ""
        wscript.echo " Note that there is documentation on the HVRemote site to assist with the"
        wscript.echo " most commonly asked questions. Please consult that before asking for"
        wscript.echo " assistance."
        wscript.echo "-------------------------------------------------------------------------------"
    end if

    ' Server side (v0.7) Warning of no connectivity test
    if (NO_ERROR = lReturn) and _
       (glClientServerMode = HVREMOTE_MODE_SERVER) And _
       (gbShowMode) And _
       (not gbTestConnectivity) THen
        wscript.echo ""
        wscript.echo ""
        wscript.echo ""
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Did you know.... HVRemote can help diagnose common errors?"
        wscript.echo ""
        wscript.echo " Instead of running HVRemote /show, run HVRemote /show /target:clientname."
        wscript.echo " This runs tests against the client to verify potential connectivity issues."
        wscript.echo ""
        wscript.echo " Note that there is documentation on the HVRemote site to assist with the"
        wscript.echo " most commonly asked questions. Please consult that before asking for"
        wscript.echo " assistance."
        wscript.echo "-------------------------------------------------------------------------------"
    end if

    wscript.echo "INFO: HVRemote complete"


'------------------------------------ END OF MAIN ----------------------------------------


 

    ' ********************************************************************
    ' * Logs a debug message. In a function in case I change to file logging some time...
    ' ********************************************************************
     Function Dbg (lLevel, szMessage)
         if (lLevel <= glDebugLevel) Then wscript.echo "DEBUG: " & szMessage
     End Function


    ' ********************************************************************
    ' * Displays and error. In a function in case I change it to log to file some time...
    ' ********************************************************************
     Function Error (szMessage)
        wscript.echo  "***** " & szMessage
     End Function


    ' ********************************************************************
    ' * DoClientChecks: SKU and KB checks 
    ' ********************************************************************
    Function DoClientChecks(oConnection) ' Connection to CIMv2 namespace

        Dim lReturn                    ' Function return value
        Dim szProgramFiles             ' Environment %ProgramFiles%
        Dim aVersion                   ' For splitting the .version property

        On error resume next

        lReturn = NO_ERROR
        szProgramFiles = ""
        aVersion = split(goLocalWin32OS.Version,".")

        ' Bail out if we aren't on a client SKU
        ' 1=Ultimate; 2=HomeBasic; 3=HomeBasicPremium; 4=Enterprise; 5=HomeBasicN; 6=Business;
        ' 11=Starter; 16=BusinessN; 48=Professional; 49=ProfessionalN

        if glInstalledOS = HVREMOTE_INSTALLED_OS_SERVER Then   ' This is easier than lots of SKU checks :)
            wscript.echo "INFO: This appears to be a server SKU"
            Exit function
        End If

        ' Vista Version
        if (WIN_6 = glOSRelease) Then
            ' http://msdn.microsoft.com/en-us/library/aa394239(VS.85).aspx
            ' 2=HomeBasic; 3=HomeBasicPremium; 5=HomeBasicN; 11=Starter
            if (goLocalWin32OS.OperatingSystemSKU = 2) or _
               (goLocalWin32OS.OperatingSystemSKU = 3) or _
               (goLocalWin32OS.OperatingSystemSKU = 5) or _
               (goLocalWin32OS.OperatingSystemSKU = 11) Then
                 Error ""
                 Error "The Vista SKU you are using does not support Hyper-V Remote Management"
                 Error "SKU ID Found is " & goLocalWin32OS.OperatingSystemSKU
                 Error "SKU info on http://msdn.microsoft.com/en-us/library/aa394239(VS.85).aspx"
                 wscript.quit
            end if
                    

            ' KB952627 check - v1 RTM Management Update
            if IsQFEInstalled(oConnection, "952627") then
                wscript.echo "INFO: This machine has Hyper-V Management Client installed (KB952627)"
            else
                Error ""
                Error "You need to install KB952627 for Hyper-V Remote Management from Vista"
                Error "http://support.microsoft.com/kb/952627"
                wscript.quit
            end if


            ' KB970203 check for Vista SP2 - update to Management bits
            if CLng(aVersion(2)) = 6002 then
                if IsQFEInstalled(oConnection, "970203") then
                    wscript.echo "INFO: Found recommended update KB970203"
                else
                    glWarns = glWarns + 1
                    gszWarns = gszWarns & glWarns & ": Recommended update KB970203 is not installed" & vbcrlf
                end if
            end if ' End of Vista SP2 check

        end if ' End of check if running Windows Vista


        ' Windows 7 Version  checks
        if (WIN_7 = glOSRelease) Then

            ' http://msdn.microsoft.com/en-us/library/aa394239(VS.85).aspx
            ' 2=HomeBasic; 3=HomeBasicPremium; 5=HomeBasicN; 11=Starter
            if (goLocalWin32OS.OperatingSystemSKU = 2) or _
               (goLocalWin32OS.OperatingSystemSKU = 3) or _
               (goLocalWin32OS.OperatingSystemSKU = 5) or _
               (goLocalWin32OS.OperatingSystemSKU = 11) Then
                Error ""
                Error "The Windows 7 SKU you are using does not support Hyper-V Remote Management"
                Error "SKU ID Found is " & goLocalWin32OS.OperatingSystemSKU
                Error "SKU info on http://msdn.microsoft.com/en-us/library/aa394239(VS.85).aspx"
 
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": This Windows 7 edition does not support the Hyper-V Tools" & vbcrlf
                wscript.quit
            end if

            if IsQFEInstalled(oConnection, "958830") then                    
                wscript.echo "INFO: Remote Server Administration Tools are installed"
            else
                ' http://www.microsoft.com/downloads/details.aspx?FamilyID=7d2f6ad7-656b-4313-a005-4e344e43997d
                wscript.echo ""
                Error "You may need to install an update for RSAT (Remote Server"
                Error "Administration Tools) for Windows 7. You will find this"
                Error "on the Microsoft Download Centre."
                Error ""
                Error "http://tinyurl.com/yers2eq"
                wscript.echo ""

                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": RSAT does not appear to be installed" & vbcrlf
                exit function
            end if

            Call GetEnvironmentVariable("ProgramFiles", szProgramFiles)
            if len(szProgramFiles) Then
                if not(FileExists(szProgramFiles & "\Hyper-V\virtmgmt.msc")) then
                    wscript.echo ""
                    Error "RSAT is installed, but you need to enable a Windows feature to"
                    Error "run the Hyper-V Remote Management tools:"
                    Error ""
                    Error " - Start/Control Panel"
                    Error " - Click 'Programs'"
                    Error " - Click 'Turn Windows features on or off'"
                    Error " - Expand the tree to check 'Hyper-V Tools' under"
                    Error "   Remote Server Administration Tools/Role Administration Tools"
                    Error " - Click OK to enable the feature."
                    Error ""
                    Error "Once the feature is enabled, Hyper-V Manager will be"
                    Error "located under Administrative Tools."
                    wscript.echo ""

                    glWarns = glWarns + 1
                    gszWarns = gszWarns & glWarns & ": Hyper-V Tools are not enabled" & vbcrlf
                    wscript.quit
                else
                    wscript.echo "INFO: Hyper-V Tools Windows feature is enabled"
                end if
            else
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Unable to determine %programfiles%" & vbcrlf
            end if

        end if ' Windows 7 Version

        ' WIN_8 and later
        if (glOSRelease >= WIN_8) Then
  
             Call GetEnvironmentVariable("ProgramFiles", szProgramFiles)
             if len(szProgramFiles) Then
                 if not(FileExists(szProgramFiles & "\Hyper-V\Microsoft.Virtualization.Client.dll")) then
                     wscript.echo ""
                     Error "You need to enable a Windows feature to run the Hyper-V"
                     Error "Management tools:"
                     Error ""
                     Error " - From the Start screen, type 'Settings and Features'"
                     Error " - Select 'Settings' under Search at the top right"
                     Error " - Click 'Settings and Features"
                     Error " - Click 'Turn Windows features on or off'"
                     Error " - Expand the tree to check 'Hyper-V Management Tools' under"
                     Error "   Hyper-V"
                     Error " - Click OK to enable the feature."
                     Error ""
                     Error "Once the feature is enabled, Hyper-V Manager will be"
                     Error "located on the Start screen."
                     wscript.echo ""

                     glWarns = glWarns + 1
                     gszWarns = gszWarns & glWarns & ": Hyper-V Tools are not enabled" & vbcrlf
                     wscript.quit
                else
                     wscript.echo "INFO: Hyper-V Tools are enabled"
                end if
            else
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Unable to determine %programfiles%" & vbcrlf
            end if

        end if ' Windows 8 Version

    End Function

    ' ********************************************************************
    ' * CheckOSVersion: Looks to see what OS is running
    ' ********************************************************************
    Sub CheckOSVersion() 

        Dim aVersion                   ' For splitting the .version property
        On error resume next

        aVersion = split(goLocalWin32OS.Version,".")

        if CLng(aVersion(0)) < 6 then
            wscript.echo "Cannot run pre-Vista/Windows Server 2008"
            wscript.quit
        end if

        ' Assume WIN_6 as we know we're no earlier
        glOSRelease = WIN_6 

        ' New as yet untested version. Assume Windows 8
        if CLng(aVersion(0)) > 6 then
            glOSRelease = WIN_LATER
            exit sub
        end if

       ' Must be 6.x:  6.0=Vista/Longhorn. In which case must be at least SP1 for Vista. There was no Longhorn "SP0" RTM
       if CLng(aVersion(1)) = 0 then
           glOSRelease = WIN_6
           if goLocalWin32OS.ServicePackMajorVersion < 1 THen
               Error "Must have Windows Vista SP1 or later for Hyper-V Remote Management"
               wscript.quit
           end if
           exit sub
        end if

        ' 6.1=Windows 7/Windows Server 2008 R2
        if CLng(aVersion(1)) = 1 Then
            glOSRelease = WIN_7
            if CLng(aVersion(2)) < 7600 then
                wscript.echo "WARN: This is a pre-release version of Windows 7/Windows Server 2008 R2"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glwarns & ": Pre-release operating systems are not supported" & vbcrlf      
            end if
            exit sub
        end if

        ' 6.2=Windows 8/Windows Server 2012
        if (CLng(aVersion(1)) =2) Then
            glOSRelease = WIN_8 
            if CLng(aVersion(2)) < 9200 Then
                wscript.echo "WARN: This is a pre-release version of Windows 8/Windows Server 2012"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glwarns & ": Pre-release operating systems are not supported" & vbcrlf      
            end if
            exit sub
        end if


        ' 6.3=Windows 8.1/Windows Server 2012 R2
        if (CLng(aVersion(1)) =3) Then
            glOSRelease = WIN_8POINT1 
            if CLng(aVersion(2)) < 9600 Then
                wscript.echo "WARN: This is a pre-release version of Windows 8.1/Windows Server 2012 R2"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glwarns & ": Pre-release operating systems are not supported" & vbcrlf      
            end if
            exit sub
        end if

        ' 6.x where x>3
        if (CLng(aVersion(1)) >3) Then
            glOSRelease = WIN_LATER
'## Keep for next release...
'            if CLng(aVersion(2)) < 9431 Then 'BUGBUG Need final build number and remove experimental comment for final release.
'                wscript.echo "WARN: This version of Windows 8.1/Windows Server 2012 R2 is pre-preview" 
'                wscript.echo "      Support for this operating system is experimental."
'                glWarns = glWarns + 1
'                gszWarns = gszWarns & glwarns & ": Pre-release operating systems are not supported" & vbcrlf      
'            end if
'
'            if CLng(aVersion(2)) = 9431 Then 'BUGBUG Need final build number and remove experimental comment for final release.
'                wscript.echo "WARN: This is the preview version of Windows 8.1/Windows Server 2012 R2" 
'                wscript.echo "      Support for this operating system is experimental."
'                glWarns = glWarns + 1
'                gszWarns = gszWarns & glwarns & ": Preview operating systems are not supported" & vbcrlf      
'            end if
'
'            if CLng(aVersion(2)) > 9431 Then 'BUGBUG Need final build number and remove experimental comment for final release.
'                wscript.echo "WARN: This is a unknown version of Windows 8.1/Windows Server 2012 R2" 
'                wscript.echo "      Support for this operating system is experimental."
'                glWarns = glWarns + 1
'                gszWarns = gszWarns & glwarns & ": Unknown/untested operating systems are not supported" & vbcrlf      
'            end if
            exit sub
        end if


    End Sub

    ' ********************************************************************
    ' * GetLocalWin32CSAndOS: Obtains WMI objects for computer and OS
    ' ********************************************************************
    Sub GetLocalWin32CSAndOS(oConnection)

        Dim colCSs
        Dim colOSs
        Dim oOS
        Dim oCS

        set colCSs = Nothing
        set colOSs = Nothing
        set oOS = Nothing
        set oCS = Nothing

        On error resume next

        set colOSs = oConnection.ExecQuery("select * from win32_operatingsystem")
        if (err.number = 0) Then
             for each oOS in colOSs
                 set goLocalWin32OS = oOS
             next
        end if

        set colCSs = oConnection.ExecQuery("select * from win32_computersystem")
        if (err.number = 0) Then
             for each oCS in colCSs
                 set goLocalWin32CS = oCS
             next
        end if

        if (err.number) or (goLocalWin32OS is nothing) or (goLocalWin32CS is nothing) Then
            Error "Failed to obtain local computer information"
            Error err.description & " " & err.number
            wscript.quit
        end if

        set colCSs = Nothing
        set colOSs = Nothing
        set oOS = Nothing
        set oCS = Nothing

    End Sub


    ' ********************************************************************
    ' * DisplayAuthorizationStore: Dumps out AZMan policy store
    ' ********************************************************************
    Function DisplayAuthorizationStore(oAuthStore, szRoleAssignment)

        Dim lReturn
        Dim oApplication            ' The Application Object
        Dim oOperation              ' For enumerating the operations in the policy store
        Dim colOperations           ' The collection of all operations in the policy store
        Dim colRoleAssignments      ' The collection of all role assignments in the policy store. Default 1 'Administrators'
        Dim oRoleAssignment         ' For enumerating the role assignments in the policy store
        Dim lIndex                  ' For enumerating operations
        Dim arrOperations           ' For extracting operations from roleassignment.roledefinition.operations 
        Dim bRoleAssignmentFound    ' Is the requested role assignment present in the policy store?
        Dim iRoleAssignmentCount    ' For iterating the role assignments
        Dim bIsLocalGroup           ' Hopefully self evident (?)

        On error resume next

        lReturn = NO_ERROR
        bRoleAssignmentFound = FALSE
        set oApplication = NOthing
        set oOperation = Nothing
        set oRoleAssignment = Nothing

        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Contents of Authorization Store Policy"
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo " "

        wscript.echo "Hyper-V Registry configuration:"
        wscript.echo "- Store: " & gszAuthStore
        wscript.echo "- Service Application: " & gszAuthStoreServiceApplication
        wscript.echo " "

        ' Verify the number of applications. Should be 1.
        If (NO_ERROR = lReturn) Then
            If 1 <> oAuthStore.Applications.Count Then
                Error "ERROR: Should be 1 application in policy store. There are " & oAuthStore.Applications.Count
                lReturn = -1
            Else
                wscript.echo "Application Name: " & oAuthStore.Applications.Item(1).Name
                if lcase(gszAuthStoreServiceApplication) <> lcase (oAuthStore.Applications.Item(1).Name) Then
                    Error "Authorization store is not the configured Hyper-V Authorization store."
                    Error "It should contain application '" & gszAuthStoreServiceApplication & "'"
                    Error "It actually contains " & oAuthStore.Applications.Item(1).Name
                    lReturn = -1
                else
                    Set oApplication = oAuthStore.OpenApplication(gszAuthStoreServiceApplication)
                    if (err.number) or (oApplication is nothing) Then
                        Error "Failed to open application in authorization store"
                        Error err.number & " " & err.description
                        lReturn = -1
                    end if
                end if
            End If
        End If

        ' Dump the entire set of operations
        If (NO_ERROR = lReturn) Then
            wscript.echo "Operation Count: " & oApplication.Operations.Count
            wscript.echo " "
            Set colOperations = oApplication.Operations
            For Each oOperation In colOperations
                wscript.echo "    " & oOperation.OperationID & " - " & oOperation.Name
            Next
            wscript.echo " "
        End If

        ' How many Role Assignments are defined? (Default is Administrators only)
        If (NO_ERROR = lReturn) Then
            wscript.echo oAuthStore.Applications.Item(1).RoleAssignments.Count & " role assignment(s) were located"
            Set colRoleAssignments = oApplication.RoleAssignments
            If oApplication.RoleAssignments.Count = 0 Then
                wscript.echo "ERROR: The policy store has no role assignments!"
                lReturn = -1
            End If
        End If


        If (NO_ERROR = lReturn) Then


            For iRoleAssignmentCount = 1 to oApplication.RoleAssignments.Count

                set oRoleAssignment = oApplication.OpenRoleAssignment(oApplication.RoleAssignments(iRoleAssignmentCount).Name)
                wscript.echo " "
                Dim szTemp
                szTemp = "Role Assignment '" & oRoleAssignment.Name & "' "
                If LCase(oRoleAssignment.Name) = LCase(szRoleAssignment)Then
                   szTemp = szTemp & "(Targetted Role Assignment)"
                   bRoleAssignmentFound = True
                End If
                wscript.echo szTemp

                If (oRoleAssignment.RoleDefinitions.Count < 1) Then
                     Error "ERROR: Cannot handle role assignments with no role definitions!!!"
                     wscript.Quit
                Else
                    
                    arrOperations = oRoleAssignment.RoleDefinitions.Item(1).Operations
                    
                    if ubound(arrOperations) + 1 < oApplication.Operations.Count then
                        wscript.echo "   WARN: Only the following operations are present in this role definition"
                        For lIndex = 0 To UBound(arrOperations)
                            wscript.echo "   - " & arrOperations(lIndex)
                        Next
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Some operations are not present in AZMan" & vbcrlf
                    else
                        wscript.echo "   - All Hyper-V operations are selected"
                    end if

                    ' Note to self. This is the most bizarre object model I've ever dealt with.
                    ' Cannt access through oRoleAssignment.Members(n), but assigning a local array seems to work. 
                    ' Ugh. Oh, and can get ubound property. Most odd.

                    wscript.echo "   - There are " & UBound(oRoleAssignment.Members)+1 & " member(s) for this role assignment"
                    wscript.echo " "
                    Dim arrMembers, arrMembersName
                    arrMembers = oRoleAssignment.Members
                    arrMembersName = oRoleAssignment.MembersName
                    Dim x

                    for x = 0 to ubound(arrMembers)
                       wscript.echo "   - " & arrMembersName(x) & " (" & arrMembers(x) & ")"

                      ' New for v1.03 - Detect use of local groups in a domain environment. 
                      if (not(gbComputerIsWorkGroup)) and _
                         (len(arrMembers(x))) then


                          bIsLocalGroup = False
                          ' Quick and dirty way to tell difference between BUILTIN\Groupname than BOXNAME\Groupname as in AZMan, 
                          ' for example BOXNAME\Administrators is displayed as BUILTIN\Administrators in arrMembersName, but 
                          ' when calling WMI in IsLocalGroup, you get back BOXNAME\Administrators which is a local group, which
                          ' would otherwise get flagged erroneously as a local group. 

                          if len(gszLocalComputerName) and _
                             len(arrMembersName(x)) >= len(gszLocalComputerName) then
                              if lcase(left(arrMembersName(x),len(gszLocalComputerName))) = lcase(gszLocalComputerName) Then
                                  if NO_ERROR = IsLocalGroup(arrMembers(x), bIsLocalGroup) Then
                                      if bIsLocalGroup Then
                                          wscript.echo " "
                                          wscript.echo "     *** WARN: " & arrMembersName(x) & " is a local group."
                                          wscript.echo "     ***  In a domain joined environment, you must either use domain groups"
                                          wscript.echo "     ***  or add user accounts individually."
                                          wscript.echo " "
                                          glWarns = glWarns + 1
                                          gszWarns = gszWarns & glWarns & ": Local group " & arrMembersName(x) & " found in role assignment " & szRoleAssignment & vbcrlf

                                      end if
                                  end if
                              end if
                          end if
          
                      end if   ' End if we have something which could be a local group in a domain environment

                    next
                
                End If
            Next
        End If

        if (NO_ERROR = lReturn) Then
            if (not bRoleAssignmentFound) Then 
               wscript.echo "WARN: Role Assignment '" & szRoleAssignment & "' is not in policy store"
               glWarns = glWarns + 1
               gszWarns = gszWarns & glWarns & ": Role assignment not found in policy store" & vbcrlf
            end if
        end if

        set oApplication = NOthing
        set oOperation = Nothing
        set oRoleAssignment = Nothing
        set colRoleAssignments = Nothing
        set colOperations = Nothing

        DisplayAuthorizationStore=lReturn

    End Function ' DisplayAuthorizationStore


    ' ********************************************************************
    ' * OpenAuthorizationStore: Reads registry and opens auth store
    ' ********************************************************************
    Function OpenAuthorizationStore(byref oAuthStore)
        On error resume next

        Dim lReturn           ' Function Return Value
        Dim oReg              ' StdRegProv to query registry

        On error resume next

        lReturn = NO_ERROR
        set oReg = Nothing
        set oAuthStore = Nothing

        Dbg DBG_STD, "OpenAuthorizationStore: Enter"

        ' Need StdRegProv to access the registry
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "OpenAuthorizationStore: Instantiate StdRegProv"
            set oReg=GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
            if (err.number) or (oReg is Nothing) Then
                Error "OpenAuthorizationStore failed: Could not instantiate StdRegProv"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' Get the Path to the store
        if (NO_ERROR = lReturn) then
            Dbg DBG_STD, "OpenAuthorizationStore: GetStringValue"
            lReturn = oReg.GetStringValue (HKEY_LOCAL_MACHINE, _
                                           AUTH_STORE_PATH, _
                                           AUTH_STORE_KEY, _
                                           gszAuthStore)
            if (err.number) or (lReturn) Then 
                Error "OpenAuthorizationStore failed: Failed to query registry"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if


        ' Verify is an XML file
        if (NO_ERROR = lReturn) Then
            if left(lcase(gszAuthStore),8) <> "msxml://" Then
                Error "This server is not using an XML based authorization store."
                Error "I'm assuming therefore that you already know what you are doing "
                Error "and I'm not going any further!"
                lReturn = -1
            end if
        end if

        ' Get the service application
        if (NO_ERROR = LReturn) Then

            Dbg DBG_STD, "OpenAuthorizationStore: GetStringValue"
            lReturn = oReg.GetStringValue (HKEY_LOCAL_MACHINE, _
                                           AUTH_STORE_PATH, _
                                           AUTH_STORE_SERVICE, _
                                           gszAuthStoreServiceApplication)
            if (err.number) or (lReturn) Then 
                Error "OpenAuthorizationStore failed: Failed to query registry"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then

            set oAuthStore = CreateObject("AzRoles.AzAuthorizationStore")
            if (err.number) or (oAuthStore is nothing) Then
                Error "Failed to create AzRoles.AzAuthorizationStore"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        'Open the auth store
        ' http://msdn.microsoft.com/en-us/library/aa376359(VS.85).aspx  0=Update
        if (NO_ERROR = lReturn) Then
            oAuthStore.Initialize 0, gszAuthStore
            if (err.number) or (oAuthStore is nothing) Then
                Error "Failed to open authorization store"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        set oReg = Nothing

        OpenAuthorizationStore = lReturn

    End Function

    ' ********************************************************************
    ' * AddRemoveAuthorizationStore: Adds or removes user/group
    ' ********************************************************************
    Function AddRemoveAuthorizationStore(oAuthStore, szRoleAssignment)


        Dim lReturn
        Dim oApplication            ' The Application Object
        Dim oRoleAssignment         ' For enumerating the role assignments in the policy store
        Dim szMemberName            ' What we are adding or removing

        On error resume next

        lReturn = NO_ERROR

        set oApplication = NOthing
        set oRoleAssignment = Nothing

        wscript.echo ""

        ' Open the application
        If (NO_ERROR = lReturn) Then
           Set oApplication = oAuthStore.OpenApplication(gszAuthStoreServiceApplication)
           if (err.number) or (oApplication is nothing) Then
               Error "Failed to open application in authorization store"
               Error err.number & " " & err.description
               lReturn = -1
           End If
        End If

        ' Open the role assignment
        If (NO_ERROR = lReturn) Then
           set oRoleAssignment = oApplication.OpenRoleAssignment(szRoleAssignment)
           if (err.number) or (oRoleAssignment is nothing) Then
               Error "Failed to open role assignment " & szRoleAssignment & " in authorization store"
               Error "Try using the /show option to display the contents of the store"
               Error "Is it possible you are using a custom store, or have provided an invalid "
               Error "parameter to /roleassign?"
               Error err.number & " " & err.description
               lReturn = -1
           End If
        End If


        ' Add or remove the user
        if (NO_ERROR = lReturn) Then

            szMemberName = ""
            if len(gszServerOpAddOrRemoveDomainName) Then
                szMemberName = szMemberName & gszServerOpAddOrRemoveDomainName & "\"
            end if
            szMemberName = szMemberName & gszServerOpAddOrRemoveUserName

            if (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) Then
                wscript.echo "Adding " & szMemberName & " to AZMan role " & szRoleAssignment
                lReturn = oRoleAssignment.AddMemberName(szMemberName)
                select case err.number
                   case &H800700B7
                      wscript.echo "WARN: " & szMemberName & " is already in AZMan Role " & szRoleAssignment
                      wscript.echo "INFO: No action taken here"
                      err.clear
                      lReturn = NO_ERROR
                   case 0
                      lReturn = NO_ERROR
                   case else
                      ' The object model seems very fragile. Just in case, not quitting IF
                      ' hit a different error. Just let the user know, but keep going
                      wscript.echo "ERROR: Could not add " & szMemberName & " to AZMan Role " & szRoleAssignment
                      wscript.echo err.description & " " & hex(err.number)
                      err.clear
                      lReturn = NO_ERROR
                end select
            else
                wscript.echo "Removing " & szMemberName & " from AZMan role " & szRoleAssignment
                lReturn = oRoleAssignment.DeleteMemberName(szMemberName)
                select case err.number
                   case &H80070490
                      wscript.echo "WARN: " & szMemberName & " is not in AZMan Role " & szRoleAssignment
                      wscript.echo "INFO: No action taken here"
                      err.clear
                      lReturn = NO_ERROR
                   case 0
                      lReturn = NO_ERROR
                   case else
                      ' The object model seems very fragile. Just in case, not quitting IF
                      ' hit a different error. Just let the user know, but keep going
                      wscript.echo "ERROR: Could not remove " & szMemberName & " from AZMan Role " & szRoleAssignment
                      wscript.echo err.description & " " & hex(err.number)
                      err.clear
                      lReturn = NO_ERROR
                end select
            end if

            ' Submit anyway. As I say, I was struggling with fragility in the object model        
            oRoleAssignment.submit 0,0
            if (err.number) Then
                wscript.echo "ERROR after submit, but ignoring: " & err.description & " " & hex(err.number)
                err.clear
            end if

        End If


        set oApplication = NOthing
        set oRoleAssignment = Nothing

        AddRemoveAuthorizationStore=lReturn

    End Function




    ' ********************************************************************
    ' * ChangeFirewallPolicyForGroup: Enables or disables a firewall group
    ' ********************************************************************
    Function ChangeFirewallPolicyForGroup(szFirewallGroup, bDesiredEnabledValue)

        ' Based on sample from http://msdn.microsoft.com/en-us/library/aa364721(VS.85).aspx

        Dim lCurrentProfiles        ' Bitmask of the firewall profiles currently active.
        Dim arrInterfaces           ' Array of interfaces to which rule is excluded
        Dim lInterface              ' Looping through each of the excluded interfaces
        Dim oRule                   ' For enumerating through each of the rules
        Dim lNumChanged             ' Number of rules which are not in the desired enabled/disabled state
        Dim lReturn                 ' Function return value
        Dim oFWPolicy2              ' Object referencing the current firewall policy
        Dim lNumFound               ' Number of matching firewall rules

        lNumChanged = 0
        lNumFound = 0
        lReturn = NO_ERROR
        set oRule = Nothing
        set oFWPolicy2 = Nothing

        On error resume next

        if (not(gbIsFirewallRunning)) Then
            wscript.echo ""
            Error ""
            Error "Skipping. The firewall is not running or turned off"
            Error ""
            lReturn = -1
            Exit function
        end if



        ' Create the FwPolicy2 object.
        if (NO_ERROR = lReturn) Then
            Set oFWPolicy2 = CreateObject("HNetCfg.FwPolicy2")
            if (err.number) or (oFWPolicy2 is nothing) Then
                Error "Failed to create HNetCfg.FwPolicy2 object"
                Error err.description & " " & lReturn
                lReturn = -1
            end if
        end if

        
        ' Print all the rules.
        if (NO_ERROR = lReturn) Then
            For Each oRule In oFWPolicy2.Rules
                if lcase(oRule.Grouping) = LCase(szFirewallGroup) then

                    lNumFound = lNumFound + 1
                    if oRule.Enabled <> bDesiredEnabledValue Then
                        lNumChanged = lNumChanged + 1
                        oRule.Enabled = bDesiredEnabledValue
                        if err.number Then
                            Error "Failed to update firewall rule"
                            Error err.description & " " & err.number
                            Error "You must be running from an elevated command prompt"
                            wscript.quit
                        end if
                        if bDesiredEnabledValue then
                           wscript.echo "INFO: Enabled firewall rule " & oRule.Name
                        else
                            wscript.echo "INFO: Disabled firewall rule " & oRule.Name
                        end if
                    else
                        wscript.echo "WARN: " & oRule.Name & " firewall not updated"
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Firewall Rule " & oRule.Name & " was not updated" & vbcrlf
                    end if

                end if
            Next

        end if

        if (NO_ERROR = lReturn) and (lNumFound = 0) Then
            Error "No firewall rules found in rule group " & szFirewallGroup
            lReturn = -1
        end if



        if lNumChanged Then wscript.echo "INFO: " & lNumChanged & " firewall rule(s) updated"

        set oRule = Nothing
        set oFWPolicy2 = Nothing

        ChangeFirewallPolicyForGroup = lReturn

    End Function ' ChangeFirewallPolicyForGroup


    ' ********************************************************************
    ' * ShowFirewallPolicyForGroup: Dumps out firewall group
    ' ********************************************************************
    Function ShowFirewallPolicyForGroup(szFirewallGroup, szFriendlyName, bCheckDesiredEnabledValue, bDesiredEnabledValue)

        Dim lCurrentProfiles        ' Bitmask of the firewall profiles currently active.
        Dim arrInterfaces           ' Array of interfaces to which rule is excluded
        Dim lInterface              ' Looping through each of the excluded interfaces
        Dim oRule                   ' For enumerating through each of the rules
        Dim lNotDesired             ' Number of rules which are not in the desired enabled/disabled state
        Dim lReturn                 ' Function return value
        Dim oFWPolicy2              ' Object referencing the current firewall policy
        Dim lNumDAIncompatible      ' Number of firewall rules which are not compatible with DA (client only)


        lNotDesired = 0
        lReturn = NO_ERROR
        set oRule = Nothing
        set oFWPolicy2 = Nothing
        lNumDAIncompatible = 0

        On error resume next

        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Firewall Settings for " & szFriendlyName
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo " "

        if (not(gbIsFirewallRunning)) Then
            Error "Skipping. The firewall is not running or turned off"
            glWarns = glWarns + 1
            gszWarns = gszWarns & glWarns & ": Firewall not running (skipped " & szFriendlyName & ")" & vbcrlf
            Exit function
        end if


        ' Create the FwPolicy2 object.
        if (NO_ERROR = lReturn) Then
            Set oFWPolicy2 = CreateObject("HNetCfg.FwPolicy2")
            if (err.number) or (oFWPolicy2 is nothing) Then
                Error "Failed to create HNetCfg.FwPolicy2 object"
                Error err.description & " " & lReturn
                lReturn = -1
            end if
        end if

        ' Get and display the current profile type
        '// The returned 'CurrentProfiles' bitmask can have more than 1 bit set if multiple profiles 
        '//   are active or current at the same time
        if (NO_ERROR = lReturn) Then
            lCurrentProfiles = oFWPolicy2.CurrentProfileTypes
            if ( lCurrentProfiles AND NET_FW_PROFILE2_DOMAIN ) then  WScript.Echo("Domain Firewall Profile is active")
            if ( lCurrentProfiles AND NET_FW_PROFILE2_PRIVATE ) then WScript.Echo("Private Firewall Profile is active")
            if ( lCurrentProfiles AND NET_FW_PROFILE2_PUBLIC ) then  WScript.Echo("Public Firewall Profile is active")
            wscript.echo " "
        end if

        
        ' Print all the rules.
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "Rules:"

            For Each oRule In oFWPolicy2.Rules
                if lcase(oRule.Grouping) = LCase(szFirewallGroup) then
                    Dim szTemp
                    szTemp = "   "
                    if oRule.Enabled Then 
                       szTemp = szTemp & "Enabled:  "
                    else
                       szTemp = szTemp & "Disabled: "
                    end if
                    szTemp = szTemp & oRule.Name & " "

                    if szFirewallGroup = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE then

                       ' 1.03 Only if configured for DA
                       if (gbConfiguredForDA) Then
                           if oRule.Direction = NET_FW_RULE_DIR_IN then
                               if oRule.EdgeTraversal = False then
                                  lNumDAIncompatible = lNumDAIncompatible + 1
                                  szTemp = szTemp & " ***"
                                  glWarns = glWarns + 1
                                  gszWarns = gszWarns & glWarns & ": " & oRule.Name & " is not DA compatible" & vbcrlf
                               end if
                            end if
                        end if
                    end if

                    wscript.echo szTemp
                    Dbg DBG_STD,"        ----------------------------------------------"
                    Dbg DBG_STD,"  Description:        " & oRule.Description
                    Dbg DBG_STD,"  Application Name:   " & oRule.ApplicationName
                    Dbg DBG_STD,"  Service Name:       " & oRule.ServiceName
                    Select Case oRule.Protocol
                        Case NET_FW_IP_PROTOCOL_TCP    Dbg DBG_STD,"  IP Protocol:        TCP."
                        Case NET_FW_IP_PROTOCOL_UDP    Dbg DBG_STD,"  IP Protocol:        UDP."
                        Case NET_FW_IP_PROTOCOL_ICMPv4 Dbg DBG_STD,"  IP Protocol:        UDP."
                        Case NET_FW_IP_PROTOCOL_ICMPv6 Dbg DBG_STD,"  IP Protocol:        UDP."
                        Case Else                      Dbg DBG_STD,"  IP Protocol:        " & oRule.Protocol
                    End Select
                    if oRule.Protocol = NET_FW_IP_PROTOCOL_TCP or oRule.Protocol = NET_FW_IP_PROTOCOL_UDP then
                        Dbg DBG_STD,"  Local Ports:        " & oRule.LocalPorts
                        Dbg DBG_STD,"  Remote Ports:       " & oRule.RemotePorts
                        Dbg DBG_STD,"  LocalAddresses:     " & oRule.LocalAddresses
                        Dbg DBG_STD,"  RemoteAddresses:    " & oRule.RemoteAddresses
                    end if
                    if oRule.Protocol = NET_FW_IP_PROTOCOL_ICMPv4 or oRule.Protocol = NET_FW_IP_PROTOCOL_ICMPv6 then
                        Dbg DBG_STD,"  ICMP Type and Code:    " & oRule.IcmpTypesAndCodes
                    end if
                    Select Case oRule.Direction
                        Case NET_FW_RULE_DIR_IN  Dbg DBG_STD,"  Direction:          In"
                        Case NET_FW_RULE_DIR_OUT Dbg DBG_STD,"  Direction:          Out"
                    End Select

                    'WScript.Echo("        Enabled:            " & oRule.Enabled)
                    if bCheckDesiredEnabledValue Then
                        if oRule.enabled <> bDesiredEnabledValue Then
                    '        wscript.echo "**** This is not the desired value for the selected operation"
                            lNotDesired = lNotDesired + 1
                        end if
                    end if
                    Dbg DBG_STD,"  Edge:               " & oRule.EdgeTraversal
                    Select Case oRule.Action
                        Case NET_FW_ACTION_ALLOW  Dbg DBG_STD,"  Action:             Allow"
                        Case NET_FW_ACTION_BLOCk  Dbg DBG_STD,"  Action:             Block"
                    End Select
                    Dbg DBG_STD,"  Grouping:           " & oRule.Grouping
                    Dbg DBG_STD,"  Interface Types:    " & oRule.InterfaceTypes
                    arrInterfaces = oRule.Interfaces
                    if IsEmpty(arrInterfaces) then
                        Dbg DBG_STD,"There are no excluded interfaces"
                    else
                        Dbg DBG_STD,"Excluded interfaces: "
                        for lInterface = lBound(arrInterface) To UBound(arrInterface)
                            Dbg DBG_STD,"    " & arrInterfaces(lInterface)
                        Next
                    end if
                end if
            Next

            if szFirewallGroup = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE then
                if (gbConfiguredForDA) then
                    if (lNumDAIncompatible > 0) then
                        wscript.echo ""
                        wscript.echo "   WARNING: Rules marked *** are not compatible with Direct Access (DA)."
                        wscript.echo "   If you do not use DA, this can be ignored."
                        wscript.echo ""
                        wscript.echo "   Use hvremote /mode:client /DA:enable to enable"
                        wscript.echo "   See http://tinyurl.com/26a48k2 for more information."
                        ' Full URL: http://blogs.technet.com/b/edgeaccessblog/archive/2010/06/21/enabling-hyper-v-management-through-directaccess.aspx
                    else
                        wscript.echo " "
                        wscript.echo "   NOTE: Inbound rules are compatible with Direct Access (DA)."
                    end if
                end if
            end if

        end if

        if (NO_ERROR = lReturn) And (bCheckDesiredEnabledValue) and (lNotDesired) Then
            wscript.echo ""
            wscript.echo "WARN: " & lNotDesired & " rules in the firewall group are not in the desired mode!"
            glWarns = glWarns + 1
            gszWarns = gszWarns & glWarns & ": Found some firewall rules in non-desired mode" & vbcrlf
         
        end if

        ShowFirewallPolicyForGroup = lReturn

        set oRule = Nothing
        set oFWPolicy2 = Nothing


    End Function ' ShowFirewallPolicyForGroup

    ' ********************************************************************
    ' * SetDAFirewallRules: Changes inbound client FW rules to be DA compatible (or not). New 1.03
    ' ********************************************************************
    Function SetDAFirewallRules(bDesiredEnabledState)


        Dim lCurrentProfiles        ' Bitmask of the firewall profiles currently active.
        Dim arrInterfaces           ' Array of interfaces to which rule is excluded
        Dim lInterface              ' Looping through each of the excluded interfaces
        Dim oRule                   ' For enumerating through each of the rules
        Dim lNumChanged             ' Number of rules which are not in the desired enabled/disabled state
        Dim lReturn                 ' Function return value
        Dim oFWPolicy2              ' Object referencing the current firewall policy
        Dim lNumFound               ' Number of matching firewall rules

        lNumChanged = 0
        lNumFound = 0
        lReturn = NO_ERROR
        set oRule = Nothing
        set oFWPolicy2 = Nothing

        On error resume next

        if (not(gbIsFirewallRunning)) Then
            wscript.echo ""
            Error ""
            Error "Skipping. The firewall is not running or turned off"
            Error ""
            lReturn = -1
            Exit function
        end if



        ' Create the FwPolicy2 object.
        if (NO_ERROR = lReturn) Then
            Set oFWPolicy2 = CreateObject("HNetCfg.FwPolicy2")
            if (err.number) or (oFWPolicy2 is nothing) Then
                Error "Failed to create HNetCfg.FwPolicy2 object"
                Error err.description & " " & lReturn
                lReturn = -1
            end if
        end if

        
        ' Iterate through each inbound rule in the client rule group
        if (NO_ERROR = lReturn) Then
            For Each oRule In oFWPolicy2.Rules
                if lcase(oRule.Grouping) = LCase(HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_RESOURCE) then
                    if oRule.Direction = NET_FW_RULE_DIR_IN Then
                        lNumFound = lNumFound + 1
                        if oRule.EdgeTraversal <> bDesiredEnabledState then
                            lNumChanged = lNumChanged + 1
                            oRule.EdgeTraversal = bDesiredEnabledState
                            if err.number Then
                                Error "Failed to update firewall rule"
                                Error err.description & " " & err.number
                                Error "You must be running from an elevated command prompt"
                                wscript.quit
                            end if
                            if bDesiredEnabledState then
                               wscript.echo "INFO: Enabled edge traversal for " & oRule.Name
                            else
                                wscript.echo "INFO: Disabled edge traversal for " & oRule.Name
                            end if
                        else
                            wscript.echo "WARN: " & oRule.Name & " firewall not updated"
                            glWarns = glWarns + 1
                            gszWarns = gszWarns & glWarns & ": Firewall Rule " & oRule.Name & " was not updated" & vbcrlf
                        end if
                    end if
                end if
            Next
        end if

        if (NO_ERROR = lReturn) and (lNumFound = 0) Then
            Error "No firewall rules found in rule group " & szFirewallGroup
            lReturn = -1
        end if



        if lNumChanged Then wscript.echo "INFO: " & lNumChanged & " firewall rule(s) updated"

        set oRule = Nothing
        set oFWPolicy2 = Nothing

        SetDAFirewallRules = lReturn


    End Function  ' SetDAFirewallRules


    ' ********************************************************************
    ' * ParseCommandLine: Does exactly what it says on the tin....
    ' ********************************************************************

     Sub ParseCommandLine ()   ' Note - quits if fails.
        On error resume next

        Dim szTemp          ' Used for splitting certain parameters
        Dim i               ' Loop control
        Dim aIPAddr, a, bAllNumbersAndDots  ' For parsing the /target parameter

        ' Asking for usage?
        if WScript.Arguments.Named.Exists("?") Or _
           WScript.Arguments.Named.Exists("help") Then
            Usage ""
            wscript.quit
        end if

       ' Make sure all arguments are recognised
       if wscript.arguments.count > 0 Then
           For i=0 to wscript.arguments.count -1
               if (left(lcase(wscript.arguments(i)),2)  <> "/?"                    ) and _
                  (left(lcase(wscript.arguments(i)),3)  <> "/ns"                   ) and _
                  (left(lcase(wscript.arguments(i)),3)  <> "/da"                   ) and _
                  (left(lcase(wscript.arguments(i)),4)  <> "/add"                  ) and _
                  (left(lcase(wscript.arguments(i)),5)  <> "/show"                 ) and _
                  (left(lcase(wscript.arguments(i)),5)  <> "/mode"                 ) and _
                  (left(lcase(wscript.arguments(i)),5)  <> "/help"                 ) and _
                  (left(lcase(wscript.arguments(i)),6)  <> "/debug"                ) and _
                  (left(lcase(wscript.arguments(i)),6)  <> "/trace"                ) and _
                  (left(lcase(wscript.arguments(i)),7)  <> "/nodcom"               ) and _
                  (left(lcase(wscript.arguments(i)),7)  <> "/target"               ) and _
                  (left(lcase(wscript.arguments(i)),7)  <> "/remove"               ) and _
                  (left(lcase(wscript.arguments(i)),8)  <> "/noazman"              ) and _
                  (left(lcase(wscript.arguments(i)),9)  <> "/anondcom"             ) and _
                  (left(lcase(wscript.arguments(i)),9)  <> "/override"             ) and _
                  (left(lcase(wscript.arguments(i)),9)  <> "/explicit"             ) and _
                  (left(lcase(wscript.arguments(i)),11) <> "/roleassign"           ) and _
                  (left(lcase(wscript.arguments(i)),15) <> "/noversioncheck"       ) and _
                  (left(lcase(wscript.arguments(i)),19) <> "/firewallhypervmgmt"   ) and _
                  (left(lcase(wscript.arguments(i)),21) <> "/firewallhypervclient" ) Then
                      USAGE "Unrecognised parameter " & wscript.arguments(i)
                      wscript.quit
                end if
            next
        end if


        ' Must be client mode or server mode
        if not wscript.arguments.named.exists("mode") then
            ' Are we going to default to server if the role is installed and we're not asking for any other
            ' server operations?
            if (gbIsRoleInstalled) Then 
                ' 1.03 Change to logic in Windows 8. We are going to assume client
                ' if the feature is enable, unless there is an explicit add or remove option
                ' There is no ideal here, it's our best guess at which way to go to make
                ' it easier to use client.
                if (glOSRelease >= WIN_8) and (glInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT) then
                    if ((WScript.Arguments.Named.Exists("remove")) or _
                        (WScript.Arguments.Named.Exists("add"))) Then            
                        wscript.echo "INFO: Assuming /mode:server due to add or remove option"
                        glClientServerMode = HVREMOTE_MODE_SERVER
                    else
                        wscript.echo "INFO: Assuming /mode:client even though Hyper-V Feature is enabled"
                        glClientServerMode = HVREMOTE_MODE_CLIENT
                    end if
                else
                    glClientServerMode = HVREMOTE_MODE_SERVER
                    wscript.echo "INFO: Assuming /mode:server as the role is installed"
                end if
            else
                glClientServerMode = HVREMOTE_MODE_CLIENT
                wscript.echo "INFO: Assuming /mode:client as the Hyper-V role is not installed"
            end if
        else
            select case wscript.arguments.named("mode") 
                case "client" glClientServerMode = HVREMOTE_MODE_CLIENT
                case "server" glClientServerMode = HVREMOTE_MODE_SERVER
                case else 
                     Usage "ERROR: Mode must be client or server (/mode:client|server)"
                     wscript.quit
            end select
        end if
 
        ' Client mode: Make sure no server only options have been supplied
        if (HVREMOTE_MODE_CLIENT = glClientServerMode) and _
           ((wscript.arguments.named.exists("ns")) or _
            (wscript.arguments.named.exists("noazman")) or _
            (wscript.arguments.named.exists("nodcom")) or _
            (wscript.arguments.named.exists("explicit")) or _
            (wscript.arguments.named.exists("roleassign"))  or _
            (wscript.arguments.named.exists("FirewallHyperVMgmt")) ) Then
            Usage "ERROR: One or more server options have been specified in client mode"
            wscript.quit
        end if

        ' Server mode: Make sure no client only options have been specified
        if (HVREMOTE_MODE_SERVER = glClientServerMode) and _
           ((wscript.arguments.named.exists("trace")) or _
            (wscript.arguments.named.exists("anonDCOM")) or _
            (wscript.arguments.named.exists("DA")) Or _
            (wscript.arguments.named.exists("FirewallHyperVClient")) ) Then
            Usage "ERROR: One or more client options have been specified in server mode"
            wscript.quit
        end if

        ' Debug level
        if (wscript.arguments.named.exists("debug")) then
            select case wscript.arguments.named("debug")
                case ""           glDebugLevel = DBG_STD
                case "standard"   glDebugLevel = DBG_STD
                case "verbose"    glDebugLevel = DBG_EXTRA
                case else
                    Usage "ERROR:  /debug option incorrect. [standard|verbose]"
                    wscript.quit
            end select
        end if

        ' Version checking
        if (wscript.arguments.named.exists("noversioncheck")) Then gbVersionCheck = False

        ' Override to allow newer OS to back down to latest OS version suppor                  
        if (wscript.arguments.named.exists("override")) Then gbOverride = True

        ' Client option
        ' Validate the /anonDCOM: parameter. 
        if (HVREMOTE_MODE_CLIENT = glClientServerMode) and _
           (WScript.Arguments.Named.Exists("anonDCOM")) Then 
             select case WScript.Arguments.Named("anonDCOM")
                 case "grant"   glClientOpAnonDCOMMode  = HVREMOTE_CLIENTOP_ANONDCOM_GRANT
                 case "revoke"  glClientOpAnonDCOMMode  = HVREMOTE_CLIENTOP_ANONDCOM_REVOKE
                 case else
                     Usage "ERROR: /anonDCOM option incorrect [revoke|grant]"
                     wscript.quit
             end select
        end if

        ' Client option
        ' Validate the /trace: parameter. 
        if (HVREMOTE_MODE_CLIENT = glClientServerMode) and _
           (WScript.Arguments.Named.Exists("trace")) Then 
             select case WScript.Arguments.Named("trace")
                 case "on"   glClientOpTracing  = HVREMOTE_CLIENTOP_TRACING_ON
                 case "off"  glClientOpTracing  = HVREMOTE_CLIENTOP_TRACING_OFF
                 case else
                     Usage "ERROR: /trace option incorrect [on|off]"
                     wscript.quit
             end select
        end if


        ' Server option. Add and Remove are mutually exclusive
        ' Parse the /remove:domain\user parameter
        if (HVREMOTE_MODE_SERVER = glClientServerMode) and _
           ((WScript.Arguments.Named.Exists("remove")) and _
            (WScript.Arguments.Named.Exists("add"))) Then 
            Usage "ERROR: Cannot specify /add and /remove!"
            wscript.quit
        end if

        ' Server option
        ' For Windows 8, are we adding/removing user explicitly?
        if WScript.Arguments.Named.Exists("explicit") Then
           gbExplicitAddRemove = True
        end if

        ' Server option
        ' Parse the /add:domain\user parameter. 
        if WScript.Arguments.Named.Exists("add") Then 
            glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD
            szTemp = WScript.Arguments.Named("add") 

            ' Domain must use domain\user format. Workgroup can do, but just user will do.
            if not gbComputerIsWorkgroup Then
                 if (0=instr(szTemp,"\")) Then
                    Usage "ERROR: /add: Must be in format Domain\UserOrGroup"
                    wscript.quit
                end if
            end if

            if (0<>instr(szTemp,"\")) Then
                gszServerOpAddOrRemoveDomainName   = left(szTemp,instr(szTemp,"\")-1)
                gszServerOpAddOrRemoveUserName     = mid(szTemp,len(gszServerOpAddOrRemoveDomainName)+2)
            else
                gszServerOpAddOrRemoveDomainName   = ""
                gszServerOpAddOrRemoveUserName     = szTemp
            end if


            ' 1.07 - Known issue - Christophe P. reported this. Must use non FQDN domain name. Added explicit check
            if not(gbComputerIsWorkgroup) Then
                if instr(gszServerOpAddOrRemoveDomainName,".") then
                    Usage "ERROR: /add: A non qualified domain name must be supplied." & vbcrlf & _
                          "             eg /add:domain\user, not /add:domain.com\user"
                    wscript.quit
                end if
            end if
        end if


        ' Server option
        ' Parse the /remove:domain\user parameter
        if WScript.Arguments.Named.Exists("remove") Then 
            glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE
            szTemp = WScript.Arguments.Named("remove") 
            if not gbComputerIsWorkgroup Then
                if (0=instr(szTemp,"\")) Then
                    Usage "ERROR: /remove: Must be in format Domain\UserOrGroup"
                    wscript.quit
                end if
            end if
            if (0<>instr(szTemp,"\")) Then
                gszServerOpAddOrRemoveDomainName = left(szTemp,instr(szTemp,"\")-1)
                gszServerOpAddOrRemoveUserName   = mid(szTemp,len(gszServerOpAddOrRemoveDomainName)+2)
            else
                gszServerOpAddOrRemoveDomainName   = ""
                gszServerOpAddOrRemoveUserName     = szTemp
            end if


            ' 1.07 - Known issue - Christophe P. reported this. Must use non FQDN domain name. Added explicit check
            if not(gbComputerIsWorkgroup) Then
                if instr(gszServerOpAddOrRemoveDomainName,".") then
                    Usage "ERROR: /remove: A non qualified domain name must be supplied." & vbcrlf & _
                          "             eg /remove:domain\user, not /remove:domain.com\user"
                    wscript.quit
                end if
            end if         
        end if
        
        ' Show option
        if WScript.Arguments.Named.Exists("show") Then
            if glServerOpAddRemoveUser <> HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE Then
                Usage "ERROR: /show cannot be combined with /add or /remove"
                wscript.quit
            end if
            gbShowMode = True
        end if

        ' Target option to /show. Cannot be supplied if not in show mode
        if WScript.Arguments.Named.Exists("target") then
            if gbShowMode = False then
                Usage "ERROR: /target can only be used in conjunction with /show"
                wscript.quit
            else
                gszRemoteComputerName = WScript.Arguments.Named("target")
                if 0 = len(gszRemoteComputerName) Then
                    if (HVREMOTE_MODE_CLIENT = glClientServerMode) then
                        Usage "ERROR: /target must have a server name supplied"
                    else
                        Usage "ERROR: /target must have a client name supplied"
                    end if
                    wscript.quit
                end if

                ' 1.03 Looks like a few people are using IP addresses. Look for something that looks like an IPv4 address. All numbers and 3 dots
                aIPAddr = split(gszRemoteComputerName,".")
                bAllNumbersAndDots = True
                if UBound(aIPAddr) = 3 then
                    a = 1
                    while (a <= len(gszRemoteComputerName)) and (bAllNumbersAndDots)
                        'wscript.echo mid(gszRemoteComputerName,a,1)
                        if (mid(gszRemoteComputerName,a,1) <> ".") and _
                           ( (asc(mid(gszRemoteComputerName,a,1)) < asc("0")) or (asc(mid(gszRemoteComputerName,a,1)) > asc("9")) ) Then
                               bAllNumbersAndDots = False
                        end if
                        a=a+1
                    wend
                else
                    bAllNumbersAndDots = False
                end if

                if bAllNumbersAndDots then
                    Usage "ERROR: /target must have a server name supplied (not IP)"
                    wscript.quit
                end if

                gbTestConnectivity = True
            end if
        end if
       

        ' Server option
        ' Are we NOT updating or displaying DCOM Permissions? 
        ' Must be in /add or /remove mode, or show mode
        if WScript.Arguments.Named.Exists("nodcom") Then
            if (gbShowMode = False) And (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) Then
                Usage "ERROR: Cannot use /nodcom unless in /add, /remove or /show modes"
                WScript.Quit
            end if
            glServerOpDCOMPermissions = HVREMOTE_SERVEROP_DCOMPERMISSIONS_OFF
        end if


        ' Server option
        ' Are we NOT updating or displaying AZMan settings?
        '  Must be in /add or /remove mode, or show mode
        if WScript.Arguments.Named.Exists("noazman") Then
            if (gbShowMode = False) And (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) Then
                Usage "ERROR: Cannot use /noazman unless in /add, /remove or /show modes"
                WScript.Quit
            end if
            glServerOpAZManUpdate = HVREMOTE_SERVEROP_AZMANUPDATE_OFF
        end if


        ' Server option
        ' Are we limiting this to just one namespace?
        ' Must be in /add or /remove mode, or show mode
        if WScript.Arguments.Named.Exists("ns") Then
            if (gbShowMode = False) and (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) Then
                Usage "ERROR: Cannot use /ns unless in /add, /remove or /show modes"
                WScript.Quit
            end if
    

            select case LCase(WScript.Arguments.Named("ns"))
                case "cimv2"             glServerOpNameSpacesToUse=NAMESPACE_CIMv2
                case "virtualization"    
                    if (glOSRelease > WIN_8) Then
                        Usage "ERROR: /ns:virtualization is not supported for Windows 8.1 and later"
                    else
                        glServerOpNameSpacesToUse=NAMESPACE_VIRTUALIZATION
                    end if
                case "virtualizationv2"  glServerOpNameSpacesToUse=NAMESPACE_VIRTUALIZATIONV2
                case "none"              glServerOpNameSpacesToUse=0
                case else
                    Usage "ERROR: Unrecognized /ns option [none|cimv2|virtualization|virtualizationv2]"
                    wscript.quit
            end select
        end if

        ' Server Option
        ' Enabling/Disabling/No action on the Hyper-V firewall group (server rules)
        if WScript.Arguments.Named.Exists("FirewallHyperVMgmt") Then
            select case lcase(WScript.Arguments.Named("FirewallHyperVMgmt"))
                case "enable"     glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_ALLOW
                case "disable"    glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_DENY
                case "none"       glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_NONE
                case else
                     Usage "ERROR: Unrecognised /FirewallHyperVMgmt option [enable|disable|none]"
                     wscript.quit
            end select
        end if

        ' Client option
        ' Enabling/Disabling/No action on the Hyper-V Management Client firewall
        if WScript.Arguments.Named.Exists("FirewallHyperVClient") Then
            select case lcase(WScript.Arguments.Named("FirewallHyperVClient"))
                case "enable"     glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_ALLOW
                case "disable"    glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_DENY
                case "none"       glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_NONE
                case else
                     Usage "ERROR: Unrecognised /FirewallHyperVClient option [enable|disable|none]"
                     wscript.quit
            end select
        end if

        ' Client option (new 1.03)
        ' Enabling/Disabling/No action on the DA compatibility for inbound firewall rules
        if WScript.Arguments.Named.Exists("da") Then
            select case lcase(WScript.Arguments.Named("da"))
                case "enable"     glClientOpFirewallDA = HVREMOTE_CLIENTOP_FIREWALL_DA_ENABLE
                case "disable"    glClientOpFirewallDA = HVREMOTE_CLIENTOP_FIREWALL_DA_DISABLE
                case "none"       glClientOpFirewallDA = HVREMOTE_CLIENTOP_FIREWALL_DA_None
                case else
                     Usage "ERROR: Unrecognised /DA option [enable|disable|none]"
                     wscript.quit
            end select
        end if


       
        ' Verify there is something to do (Server)
        if (glClientServerMode = HVREMOTE_MODE_SERVER) Then

           if (glServerOpAddRemoveUser = HVREMOTE_SERVEROP_ADDREMOVEUSER_NONE) and _
              (not gbShowMode) and _
              (glServerOpFirewallHyperV = HVREMOTE_SERVEROP_FIREWALL_HYPERV_NONE) Then
               Usage "ERROR: No server actions to perform"
               wscript.quit
           end if
        end if

        ' Verify there is something to do (Client)
        if (glClientServerMode = HVREMOTE_MODE_CLIENT) Then
           if (glClientOpFirewallHyperVMgmtClient = HVREMOTE_CLIENTOP_FIREWALL_HYPERVMGMTCLIENT_NONE) and _
              (not gbShowMode) and _
              (glClientOpFirewallDA               = HVREMOTE_CLIENTOP_FIREWALL_DA_NONE ) and _
              (glClientOpAnonDCOMMode             = HVREMOTE_CLIENTOP_ANONDCOM_NONE) and _
              (glClientOpTracing                  = HVREMOTE_CLIENTOP_TRACING_NONE) Then
               Usage "ERROR: No client actions to perform"
               wscript.quit
           end if
        end if

        ' Alternate role definition?
        if (WScript.Arguments.Named.Exists("roleassign")) and _
           (glClientServerMode = HVREMOTE_MODE_SERVER) Then
            gszRoleAssign = WScript.Arguments.Named("roleassign")
        end if


        Dbg DBG_EXTRA,  "   Client or Server Mode (1=Client)        " & glClientServerMode
        Dbg DBG_EXTRA,  "   Show mode?                              " & gbShowMode
        Dbg DBG_EXTRA,  "   Target mode?                            " & gbTestConnectivity 
        Dbg DBG_EXTRA,  "S: AZMan Update          (1=Yes)           " & glServerOpAZManUpdate                    
        Dbg DBG_EXTRA,  "S: Add or Remove User    (1=Add)           " & glServerOpAddRemoveUser
        Dbg DBG_EXTRA,  "S: Add/Remove User/Group                   " & gszServerOpAddOrRemoveUserName
        Dbg DBG_EXTRA,  "S: Add/Remove Domain                       " & gszServerOpAddOrRemoveDomainName
        Dbg DBG_EXTRA,  "S: Doing DCOM update or display?           " & glServerOpDCOMPermissions
        Dbg DBG_EXTRA,  "S: Domain AZMan update or display          " & glServerOpAZManUpdate
        Dbg DBG_EXTRA,  "S: Namespaces (1=Cimv2;2=Virtualizaiton)   " & glServerOpNameSpacesToUse
        Dbg DBG_EXTRA,  "S: Update FW Hyper-V (1=Yes)               " & glServerOpFirewallHyperV
        Dbg DBG_EXTRA,  "S: Role Assignment                         " & gszRoleAssign
        Dbg DBG_EXTRA,  "C: Update FW Hyper-V Rmt Mgmt Clnt (1=yes) " & glClientOpFirewallHyperVMgmtClient
        Dbg DBG_EXTRA,  "C: Update FW DA (1=yes)                    " & glClientOpFirewallDA
        Dbg DBG_EXTRA,  "C: Update Anon DCOM      (1=Grant)         " & glClientOpAnonDCOMMode  

    End Sub 'ParseCOmmandLine

    ' ********************************************************************
    ' * DoesAnonymousLogonHaveRemoteDCOM: Yes or No.
    ' ********************************************************************

    Function DoesAnonymousLogonHaveRemoteDCOM(oWin32SD)
        On error resume next

        Dim oACE
        DoesAnonymousLogonHaveRemoteDCOM = False

        for each oACE in oWin32SD.DACL
            if oACE.AceType = ADS_ACETYPE_ACCESS_ALLOWED and _
               oACE.Trustee.SIDString = SID_ANONYMOUS Then
                if oACE.AccessMask AND ACCESS_PERMISSION_REMOTE_ACCESS Then
                    DoesAnonymousLogonHaveRemoteDCOM  = True
                    exit function
                end if
            end if
        next

        set oACE = Nothing

    End Function ' DoesAnonymousLogonHaveRemoteDCOM


    ' ********************************************************************
    ' * AddAnonymousLogonToRemoteDCOM: Sets the SD
    ' ********************************************************************

    Function AddAnonymousLogonToRemoteDCOM(oConnection, oWin32SD)

        On error resume next

        Dim oACE           ' Looping through ACEs in the DACL
        Dim bPresent       ' Does ANONYMOUS LOGON appear in the DACL already?
        Dim arrDACL        ' ACEs in the DACL
        Dim lMaxACE        ' Number of ACEs in the DACL
        Dim oTrustee       ' Trustee for the anonymous logon account
        Dim oAnonLogonACE  ' Existing ACE for anonymous logon
        Dim oWin32SDHelper ' To convert Win32 SD to binary SD
        Dim aBinarySD      ' New SD in binary format
        Dim oReg           ' StdRegProv for writing the registry
        Dim lReturn        ' Function return value

        set oACE = nothing
        set oReg = Nothing
        bPresent = False
        set oTrustee = nothing
        set oAnonLogonACE = Nothing
        set oWin32SDHelper = Nothing
        lReturn = NO_ERROR

        Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM()"

        ' Look to see if the anonymous logon SID already exists
        if (NO_ERROR = lReturn) Then
            for each oACE in oWin32SD.DACL
                if oACE.AceType = ADS_ACETYPE_ACCESS_ALLOWED and _
                   (lcase(oACE.Trustee.SIDString) = lcase(SID_ANONYMOUS)) Then
                        bPresent = True
                        set oAnonLogonACE = oACE
                        Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: An ACE exists"
                end if
            next
        End if

        ' We need a trustee object for the anonyomus logon account
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Need to get Trustee for ANONYMOUS LOGON SID"
            lReturn = GetTrusteeForSID (SID_ANONYMOUS, oTrustee)
            if (lReturn) Then
                Error "FAILED: Could not get Trustee for " & SID_ANONYMOUS
                lReturn = -1
            end if
        end if

        ' Add the ACE if needed (ie it's not present in the DACL)
        if (NO_ERROR = lReturn) And not(bPresent) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Need to add an ACE to the current DACL"
            ' Get the current DACL locally and resize it to add a new ACE to it. 
            lMaxACE = UBound(oWin32SD.DACL) + 1
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Resizing ACE Count to " & lMaxACE
            arrDACL = oWin32SD.DACL
            Redim Preserve arrDACL(lMaxACE)


            ' Create an object instance an populate it.
            set arrDACL(lMaxACE) = oConnection.Get("win32_ACE").SpawnInstance_
            arrDACL(lMaxACE).Properties_.Item("AccessMask") = ACCESS_PERMISSION_REMOTE_ACCESS or _
                                                              ACCESS_PERMISSION_OTHER_FLAG
            arrDACL(lMaxACE).Properties_.Item("AceFlags")   = 0
            arrDACL(lMaxACE).Properties_.Item("AceType")    = ADS_ACETYPE_ACCESS_ALLOWED
            arrDACL(lMaxACE).Properties_.Item("Trustee")    = oTrustee
 
            ' Set the DACL back in the security descriptor
            oWin32SD.Properties_.Item("DACL") = arrDACL

            if (0<>err.number) Then
                Error "AddAnonymousLogonToRemoteDCOM: Failed to Set DACL!!!" & err.description
                lReturn = -1
            end if

       end if

       ' Change the ACE if needed (ie it's already present)
       if (NO_ERROR = lReturn) and (bPresent) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Updating accessmask"
            oAnonLogonACE.AccessMask = oAnonLogonACE.AccessMask Or ACCESS_PERMISSION_REMOTE_ACCESS
       end if

       ' Change the SD back to Binary form
        ' We use a helper function to convert security descriptor formats
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Instantiate win32_securitydescriptorhelper"
            Set oWin32SDHelper = GetObject("winmgmts:root\cimv2:Win32_SecurityDescriptorHelper" )
            if (err.number) then
                Error "AddAnonymousLogonToRemoteDCOM() Failed to instantiate Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Convert the binary form to the Win32_SecurityDescriptor format
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM() Convert to Binary SD "
            oWin32SDHelper.Win32SDToBinarySD oWin32SD, aBinarySD
            if (err.number) or (oWin32SD is nothing) then
                Error "AddAnonymousLogonToRemoteDCOM() Failed to Convert BinarySD to Win32SD"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if


        ' Need StdRegProv to access the registry
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: Instantiate StdRegProv"
            set oReg=GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
            if (err.number) or (oReg is Nothing) Then
                Error "AddAnonymousLogonToRemoteDCOM:  failed: Could not instantiate StdRegProv"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' Get the Binary Security Descriptor
        if (NO_ERROR = lReturn) then
            Dbg DBG_STD, "AddAnonymousLogonToRemoteDCOM: SetBinaryValue"
            lReturn = oReg.SetBinaryValue (HKEY_LOCAL_MACHINE, _
                                           MACHINE_RESTRICTION_PATH, _
                                           MACHINE_ACCESS_RESTRICTION_KEY, _
                                           aBinarySD)
            if (err.number) or (lReturn) Then 
                Error "AddAnonymousLogonToRemoteDCOM failed: Failed to set registry"
                Error err.number & " " & err.description
                Error "Is it possible you are not running this script elevated?"
                lReturn = -1
            end if
        end if


        if (NO_ERROR = lReturn) Then
            wscript.echo "INFO: Granted Remote DCOM Access to Anonymous Logon"
            wscript.echo "WARN: See documentation for security implications"
        end if


        set oACE = nothing
        set oReg = Nothing
        bPresent = False
        set oTrustee = nothing
        set oAnonLogonACE = Nothing
        set oWin32SDHelper = Nothing

        AddAnonymousLogonToRemoteDCOM = lReturn

    End Function ' AddAnonymousLogonToRemoteDCOM



    ' ********************************************************************
    ' * RemoveAnonymousLogonFromRemoteDCOM: Sets the SD
    ' ********************************************************************

    Function RemoveAnonymousLogonFromRemoteDCOM(oWin32SD)

        On error resume next

        Dim oACE           ' The allow ACE to update
        Dim oWin32SDHelper ' To convert Win32 SD to binary SD
        Dim aBinarySD      ' New SD in binary format
        Dim oReg           ' StdRegProv for writing the registry
        Dim lReturn        ' Function return value

        set oACE = nothing
        set oReg = Nothing
        set oWin32SDHelper = Nothing
        lReturn = NO_ERROR

        Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM()"

        if (oWin32SD is Nothing) Then
            Error "RemoveAnonymousLogonFromRemoteDCOM - Passed a NULL Parameter!!"
            lReturn = -1
            wscript.quit
        end if


        ' Update the access mask in the ACE for anonymous logon SID
        if (NO_ERROR = lReturn) Then
            for each oACE in oWin32SD.DACL
                if oACE.AceType = ADS_ACETYPE_ACCESS_ALLOWED and _
                   (lcase(oACE.Trustee.SIDString) = lcase(SID_ANONYMOUS)) Then
                        oACE.AccessMask = oACE.AccessMask - ACCESS_PERMISSION_REMOTE_ACCESS
                        Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM: Updated access mask to " & oACE.AccessMask
                end if
            next
        end if



       ' Change the SD back to Binary form
        ' We use a helper function to convert security descriptor formats
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM: Instantiate win32_securitydescriptorhelper"
            Set oWin32SDHelper = GetObject("winmgmts:root\cimv2:Win32_SecurityDescriptorHelper" )
            if (err.number) then
                Error "RemoveAnonymousLogonFromRemoteDCOM() Failed to instantiate Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Convert the binary form to the Win32_SecurityDescriptor format
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM() Convert to Binary SD "
            oWin32SDHelper.Win32SDToBinarySD oWin32SD, aBinarySD
            if (err.number) or (oWin32SD is nothing) then
                Error "RemoveAnonymousLogonFromRemoteDCOM() Failed to Convert BinarySD to Win32SD"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if


        ' Need StdRegProv to access the registry
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM: Instantiate StdRegProv"
            set oReg=GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
            if (err.number) or (oReg is Nothing) Then
                Error "ARemoveAnonymousLogonFromRemoteDCOM:  failed: Could not instantiate StdRegProv"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' Get the Binary Security Descriptor
        if (NO_ERROR = lReturn) then
            Dbg DBG_STD, "RemoveAnonymousLogonFromRemoteDCOM: SetBinaryValue"
            lReturn = oReg.SetBinaryValue (HKEY_LOCAL_MACHINE, _
                                           MACHINE_RESTRICTION_PATH, _
                                           MACHINE_ACCESS_RESTRICTION_KEY, _
                                           aBinarySD)
            if (err.number) or (lReturn) Then 
                Error "RemoveAnonymousLogonFromRemoteDCOM failed: Failed to set registry"
                Error err.number & " " & err.description
                Error "Is it possible you are not running this script elevated?"
                lReturn = -1
            end if
        end if


        if (NO_ERROR = lReturn) Then
            wscript.echo "INFO Revoked Remote DCOM Access from Anonymous Logon"
        end if

        set oACE = nothing
        set oReg = Nothing
        set oWin32SDHelper = Nothing

        RemoveAnonymousLogonFromRemoteDCOM = lReturn

    End Function ' RemoveAnonymousLogonFromRemoteDCOM

    ' ********************************************************************
    ' * AddHyperVAdminsInMachineLaunchSDIfMissing: 
    ' * Updates the COM SD. Only used on Win8 Client where setup doesn't do it...
    ' ********************************************************************
    Function AddHyperVAdminsInMachineLaunchSDIfMissing(oConnection, oMachineLaunchSD)

        On error resume next

        Dim oACE           ' Looping through ACEs in the DACL
        Dim bPresent       ' Does Hyper-V Administrators appear in the DACL already?
        Dim arrDACL        ' ACEs in the DACL
        Dim lMaxACE        ' Number of ACEs in the DACL
        Dim oTrustee       ' Trustee for the Hyper-V Administrators group
        Dim oHVAdminsACE   ' Existing ACE for Hyper-V Administrators
        Dim oWin32SDHelper ' To convert Win32 SD to binary SD
        Dim aBinarySD      ' New SD in binary format
        Dim oReg           ' StdRegProv for writing the registry
        Dim lReturn        ' Function return value
        Dim bChangeNeeded  ' Is an update required?

        set oACE = nothing
        set oReg = Nothing
        bPresent = False
        set oTrustee = nothing
        set oHVAdminsACE = Nothing
        set oWin32SDHelper = Nothing
        lReturn = NO_ERROR
        bChangeNeeded = False

        Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing()"

        ' Look to see if the Hyper-V Administrators group SID already exists in the DACL
        if (NO_ERROR = lReturn) Then
            for each oACE in oMachineLaunchSD.DACL
                if oACE.AceType = ADS_ACETYPE_ACCESS_ALLOWED and _
                   (lcase(oACE.Trustee.SIDString) = lcase(SID_HYPERV_ADMINISTRATORS)) Then
                        bPresent = True
                        set oHVAdminsACE = oACE
                        Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: An ACE exists"
                end if
            next
        End if

        ' We need a trustee object for the Hyper-V Administrators group
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Need to get Trustee for Hyper-V Administrators SID"
            lReturn = GetTrusteeForSID (SID_HYPERV_ADMINISTRATORS, oTrustee)
            if (lReturn) Then
                Error "FAILED: Could not get Trustee for " & SID_HYPERV_ADMINISTRATORS
                lReturn = -1
            end if
        end if

        ' Add the ACE if needed (ie it's not present in the DACL)
        if (NO_ERROR = lReturn) And not(bPresent) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Need to add an ACE to the current DACL"
            ' Get the current DACL locally and resize it to add a new ACE to it. 
            lMaxACE = UBound(oMachineLaunchSD.DACL) + 1
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Resizing ACE Count to " & lMaxACE
            arrDACL = oMachineLaunchSD.DACL
            Redim Preserve arrDACL(lMaxACE)

            bChangeNeeded = True
            wscript.echo "INFO: Need to add Machine Launch SD for Hyper-V Administrators"

            ' Create an object instance an populate it.
            set arrDACL(lMaxACE) = oConnection.Get("win32_ACE").SpawnInstance_
            arrDACL(lMaxACE).Properties_.Item("AccessMask") = ACCESS_PERMISSION_REMOTE_ACCESS or _
                                                              ACCESS_PERMISSION_LOCAL_ACCESS or _
                                                              ACCESS_PERMISSION_REMOTE_ACTIVATION or _
                                                              ACCESS_PERMISSION_LOCAL_ACTIVATION or _
                                                              ACCESS_PERMISSION_OTHER_FLAG
            arrDACL(lMaxACE).Properties_.Item("AceFlags")   = 0
            arrDACL(lMaxACE).Properties_.Item("AceType")    = ADS_ACETYPE_ACCESS_ALLOWED
            arrDACL(lMaxACE).Properties_.Item("Trustee")    = oTrustee
            ' Set the DACL back in the security descriptor
            oMachineLaunchSD.Properties_.Item("DACL") = arrDACL

            if (0<>err.number) Then
                Error "AddHyperVAdminsInMachineLaunchSDIfMissing: Failed to Set DACL!!!" & err.description
                lReturn = -1
            end if

       end if

       ' Change the ACE if needed (ie it's already present)
       if (NO_ERROR = lReturn) and (bPresent) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Checking if need to update accessmask"

            if oHVAdminsACE.AccessMask <> ACCESS_PERMISSION_REMOTE_ACCESS + _
                                          ACCESS_PERMISSION_LOCAL_ACCESS + _
                                          ACCESS_PERMISSION_REMOTE_ACTIVATION + _
                                          ACCESS_PERMISSION_LOCAL_ACTIVATION + _
                                          ACCESS_PERMISSION_OTHER_FLAG Then

                Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Existing access mask needs updating"
                wscript.echo "INFO: Need to update Machine Launch SD for Hyper-V Administrators"
                bChangeNeeded = True
                oHVAdminsACE.AccessMask = oHVAdminsACE.AccessMask Or ACCESS_PERMISSION_REMOTE_ACCESS or _
                                                                     ACCESS_PERMISSION_LOCAL_ACCESS or _
                                                                     ACCESS_PERMISSION_REMOTE_ACTIVATION or _
                                                                     ACCESS_PERMISSION_LOCAL_ACTIVATION or _
                                                                     ACCESS_PERMISSION_OTHER_FLAG
           end if
       end if

       ' Change the SD back to Binary form
        ' We use a helper function to convert security descriptor formats
        if (NO_ERROR = lReturn) and (bChangeNeeded) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Instantiate win32_securitydescriptorhelper"
            Set oWin32SDHelper = GetObject("winmgmts:root\cimv2:Win32_SecurityDescriptorHelper" )
            if (err.number) then
                Error "AddHyperVAdminsInMachineLaunchSDIfMissing() Failed to instantiate Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Convert the binary form to the Win32_SecurityDescriptor format
        if (NO_ERROR = lReturn) and (bChangeNeeded) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing() Convert to Binary SD "
            oWin32SDHelper.Win32SDToBinarySD oMachineLaunchSD, aBinarySD
            if (err.number) or (oMachineLaunchSD is nothing) then
                Error "AddHyperVAdminsInMachineLaunchSDIfMissing() Failed to Convert BinarySD to Win32SD"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if


        ' Need StdRegProv to access the registry
        if (NO_ERROR = lReturn) and (bChangeNeeded) Then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: Instantiate StdRegProv"
            set oReg=GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
            if (err.number) or (oReg is Nothing) Then
                Error "AddHyperVAdminsInMachineLaunchSDIfMissing:  failed: Could not instantiate StdRegProv"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' Set the Binary Security Descriptor
        if (NO_ERROR = lReturn) and (bChangeNeeded) then
            Dbg DBG_STD, "AddHyperVAdminsInMachineLaunchSDIfMissing: SetBinaryValue"
            lReturn = oReg.SetBinaryValue (HKEY_LOCAL_MACHINE, _
                                           MACHINE_RESTRICTION_PATH, _
                                           MACHINE_LAUNCH_RESTRICTION_KEY, _
                                           aBinarySD)
            if (err.number) or (lReturn) Then 
                Error "AddHyperVAdminsInMachineLaunchSDIfMissing failed: Failed to set registry"
                Error err.number & " " & err.description
                Error "Is it possible you are not running this script elevated?"
                lReturn = -1
            end if
        end if


        if (NO_ERROR = lReturn) Then
            if bChangeNeeded then
                wscript.echo "INFO: Granted Hyper-V Administrators Group DCOM Launch Permissions"
            'else
                'wscript.echo "INFO: Hyper-V Administrators group has DCOM launch permission already"
            end if
        end if


        set oACE = nothing
        set oReg = Nothing
        bPresent = False
        set oTrustee = nothing
        set oHVAdminsACE = Nothing
        set oWin32SDHelper = Nothing

        AddHyperVAdminsInMachineLaunchSDIfMissing = lReturn

    End Function 'AddHyperVAdminsInMachineLaunchSDIfMissing


    ' ********************************************************************
    ' * GetMachineRestrictionSDFromRegistry: Gets the current DCOM Access
    ' * Note: Called Server Side for Machine Launch Restriction and
    ' *       client side for machine access restriction
    ' ********************************************************************
    Function GetMachineRestrictionSDFromRegistry(szRegistryKey, ByRef oWin32SD)

        On error resume next

        Dim lReturn           ' Function Return Value
        Dim oReg              ' StdRegProv to query registry
        Dim aBinarySD         ' Binary Security Descriptor from registry
        Dim oWin32SDHelper    ' To convert binary SD to Win32 SD

        lReturn = NO_ERROR
        Set oWin32SDHelper = Nothing
        set oWin32SD = Nothing
        Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Enter"

        ' Need StdRegProv to access the registry
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Instantiate StdRegProv"
            set oReg=GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
            if (err.number) or (oReg is Nothing) Then
                Error "GetMachineRestrictionSDFromRegistry failed: Could not instantiate StdRegProv"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' Get the Binary Security Descriptor
        if (NO_ERROR = lReturn) then
            Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: GetBinaryValue"
            lReturn = oReg.GetBinaryValue (HKEY_LOCAL_MACHINE, _
                                           MACHINE_RESTRICTION_PATH, _
                                           szRegistryKey, _
                                           aBinarySD)
            if (err.number) or (lReturn) Then 
                Error "GetMachineRestrictionSDFromRegistry failed: Failed to query registry"
                Error err.number & " " & err.description
                lReturn = -1
            end if
        end if


        ' We use a helper function to convert security descriptor formats
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Instantiate win32_securitydescriptorhelper"
            Set oWin32SDHelper = GetObject("winmgmts:root\cimv2:Win32_SecurityDescriptorHelper" )
            if (err.number) then
                Error "Failed to instantiate Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Convert the binary form to the Win32_SecurityDescriptor format
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Convert to Win32SD "
            oWin32SDHelper.BinarySDToWin32SD aBinarySD, oWin32SD
            if (err.number) or (oWin32SD is nothing) then
                Error "Failed to Convert BinarySD to Win32SD"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Old SD is " & oWin32SD.GetObjectText_
        end if

        Dbg DBG_STD, "GetMachineRestrictionSDFromRegistry: Exit RC=" & lReturn

        Set oWin32SDHelper = Nothing
        GetMachineRestrictionSDFromRegistry = lReturn

    End Function

    ' ********************************************************************
    ' * DisplayWin32SD: Displays a Win32_SecurityDescriptor object
    ' * Type=1 is a WMI Namespace
    ' * Type=2 is a Machine Restriction
    ' ********************************************************************
    Sub DisplayWin32SD(szDescription, lType, oWin32SD)

        Dim szOut          ' For building output string
        Dim oACE           ' Win32_ACE
        Dim lReturn        ' Function Return Value
        Dim bIsLocalGroup  ' Hopefully self evident from the name!

        set oACE = Nothing

        On error resume next

        ' Note that this function completely ignores the SACL and deals only with the DACL.

        ' Note: For valid remote access to Hyper-V you need the following example settings:
        ' JHOWARD-W7\admin (S-1-5-21-1998084992-3850808323-2978472522-1000)
        '  Allow: EnabAct RemEnab  (33)
        '  Flags: InheritAce NoPropInheritAce ValidInheritFlags  (6)

        ' http://msdn.microsoft.com/en-us/library/aa394402(VS.85).aspx 
        ' class Win32_SecurityDescriptor : __SecurityDescriptor
        ' {
        '   uint32 ControlFlags;
        '   Win32_ACE DACL[];
        '   Win32_Trustee Group;
        '   Win32_Trustee Owner;
        '   Win32_ACE SACL[];
        ' };

 
        ' http://msdn.microsoft.com/en-us/library/aa394501(VS.85).aspx
        ' class Win32_Trustee : __Trustee
        ' {
        '   string Domain;
        '   string Name;
        '   uint8 SID[];
        '   uint32 SidLength;
        '   string SIDString;
        ' }; 

        ' http://msdn.microsoft.com/en-us/library/aa394063(VS.85).aspx
        ' class Win32_ACE : __ACE
        '{
        '  uint32 AccessMask;
        '  uint32 AceFlags;
        '  uint32 AceType;
        '  string GuidInheritedObjectType;
        '  string GuidObjectType;
        '  Win32_Trustee Trustee;
        '};

        if (oWin32SD is nothing) Then
            wscript.echo "!!! There is no security descriptor to display !!!"
            exit Sub
        end if

        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        select case lType
            case 1  
                 wscript.echo "DACL for WMI Namespace " & szDescription 
                 wscript.echo "Required for Hyper-V remote mangement: Allow, EnabAct, RemEnab, InheritAce"
                 wscript.echo "HVRemote also sets NoPropInheritAce and ValidInheritFlags"
            case 2  wscript.echo "DACL for " & szDescription
        end select
        wscript.echo "-------------------------------------------------------------------------------"

        ' Loop through each DACL
        for each oACE in oWin32SD.DACL
            szOut = ""
            wscript.echo " "
            wscript.echo oACE.Trustee.Domain & "\" & oACE.Trustee.Name & "    (" & oACE.Trustee.SIDString & ")"


            ' http://msdn.microsoft.com/en-us/library/aa392712(VS.85).aspx
            if (ADS_ACETYPE_ACCESS_ALLOWED=oACE.AceType) Then szOut = szOut & "     Allow: "
            if (ADS_ACETYPE_ACCESS_DENIED =oACE.AceType) Then szOut = szOut & "     Deny:  "

            ' http://msdn.microsoft.com/en-us/library/aa392710(VS.85).aspx
            if (lType = 1) Then ' WMI Namespace
                if (oACE.AccessMask And WBEM_METHOD_EXECUTE)    Then szOut = SzOut & "Exec "
                if (oACE.AccessMask And WBEM_FULL_WRITE_REP)    Then szOut = SzOut & "FullWrt "
                if (oACE.AccessMask And WBEM_PARTIAL_WRITE_REP) Then szOut = SzOut & "PartWrt "
                if (oACE.AccessMask And WBEM_WRITE_PROVIDER)    Then szOut = SzOut & "ProvWrt "
                if (oACE.AccessMask And WBEM_ENABLE)            Then szOut = SzOut & "EnabAct "
                if (oACE.AccessMask And WBEM_REMOTE_ACCESS)     Then szOut = SzOut & "RemEnab "
                if (oACE.AccessMask And READ_CONTROL)           Then szOut = SzOut & "RdSec "
                if (oACE.AccessMask And WRITE_DAC)              Then szOut = SzOut & "EdSec "
            end if

            if (lType = 2) Then ' Machine Restriction
                if (oACE.AccessMask And ACCESS_PERMISSION_LOCAL_ACCESS)      Then szOut = SzOut & "LocalLaunch "
                if (oACE.AccessMask And ACCESS_PERMISSION_REMOTE_ACCESS)     Then szOut = SzOut & "RemoteLaunch "
                if (oACE.AccessMask And ACCESS_PERMISSION_LOCAL_ACTIVATION)  Then szOut = SzOut & "LocalActivation "
                if (oACE.AccessMask And ACCESS_PERMISSION_REMOTE_ACTIVATION) Then szOut = SzOut & "RemoteActivation "
 
            end if

            wscript.echo szOut & "(" & oACE.AccessMask & ")"

            if (lType=1) Then  ' WMI Namespace only
                'http://msdn.microsoft.com/en-us/library/aa392711(VS.85).aspx (which seems wrong)
                'Info taken from ObjectBrowser on ActiveDs Enumeration ADS_ACEFLAG_ENUM       
                szOut = "     Flags: "
                if (oACE.AceFlags And ADS_ACEFLAG_FAILED_ACCESS)            Then szOut = szOut & "FailedAccess "
                if (oACE.AceFlags And ADS_ACEFLAG_INHERIT_ACE)              Then szOut = szOut & "InheritAce "
                if (oACE.AceFlags And ADS_ACEFLAG_INHERIT_ONLY_ACE)         Then szOut = szOut & "InheritOnlyAce "
                if (oACE.AceFlags And ADS_ACEFLAG_INHERITED_ACE)            Then szOut = szOut & "InheritedAce "
                if (oACE.AceFlags And ADS_ACEFLAG_NO_PROPAGATE_INHERIT_ACE) Then szOut = szOut & "NoPropInheritAce "
                if (oACE.AceFlags And ADS_ACEFLAG_SUCCESSFUL_ACCESS)        Then szOut = szOut & "SuccessfulAccess "
                if (oACE.AceFlags And ADS_ACEFLAG_VALID_INHERIT_FLAGS)      Then szOut = szOut & "ValidInheritFlags "
              
                wscript.echo szOut & " (" & oACE.AceFlags & ")" 
            End if

            ' Useful for enhanced debugging, but turned off
            Dbg DBG_EXTRA, "DisplayWin32SD() Trustee in ACE is " & oACE.Trustee.GetObjectText_()

            ' New for v1.03 - Detect use of local groups in a domain environment. We do this for going through
            ' the DACL for the WMI namespaces only. First we check to see if the domain part of the trustee matches
            ' the local comuter name. 
            if (lType = 1) And _
               (not(gbComputerIsWorkGroup)) and _
               (lcase(gszLocalComputerName) = lcase(oACE.Trustee.Domain)) and _
               (len(oACE.Trustee.Domain)) then


                bIsLocalGroup = False
                if NO_ERROR = IsLocalGroup(oACE.Trustee.SIDString, bIsLocalGroup) Then
                    if bIsLocalGroup Then
                        wscript.echo " "
                        wscript.echo "*** WARN: " & oACE.Trustee.Domain & "\" & oACE.Trustee.Name & " is a local group."
                        wscript.echo "***  In a domain joined environment, you must either use domain groups"
                        wscript.echo "***  or add user accounts individually."
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Local group " & oACE.Trustee.Domain & "\" & oACE.Trustee.Name & " found in " & szDescription & vbcrlf

                    end if
                end if
            end if   ' End if we have something which could be a local group in a domain environment


        next

        set oACE = Nothing
             
    End Sub ' DisplayWin32SD


    ' ********************************************************************
    ' * RemoveACEFromDACL: Rebuilds the DACL with an ACE of the trustee missing 
    ' * Returns ERROR_NOT_PRESENT if not found
    ' ********************************************************************
    Function RemoveACEFromDACL(ByRef oWin32SD, oConnection, oTrustee)

        Dim lNumValidAces    ' Number of ACEs which DON'T match Trustee
        Dim oACE             ' For enumerating the ACEs in the DACL
        Dim oACEs            ' Array of ACEs we build

        On error resume next
        Dbg DBG_STD, "RemoveACEFromDACL: SID=" & oTrustee.SIDString

        Set oACE = Nothing
        RemoveACEFromDACL = NO_ERROR

        ' HARD QUIT: Don't allow any of the well known built in SIDs
        if (lcase(oTrustee.SIDString) = lcase(SID_EVERYONE)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_ANONYMOUS)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_BUILTIN_ADMINISTRATORS)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_DISTRIBUTED_COM_USERS)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_HYPERV_ADMINISTRATORS)) Then
            Error "HARD BLOCK HERE. Not manipulating that group!!!"
            wscript.quit
        end if

        lNumValidAces = 0
        for each oACE in oWin32SD.DACL
            if oACE.Trustee.SIDString <> oTrustee.SIDString Then lNumValidAces = lNumValidAces + 1
        next

        Dbg DBG_STD, "RemoveACEFromDACL: " & lNumValidAces & " of " & ubound(oWin32SD.DACL)+1

        if lNumValidAces = ubound(oWin32SD.DACL)+1 then
            wscript.echo "WARN: User is not currently in the DACL"
            RemoveACEFromDACL = ERROR_NOT_PRESENT
            exit function
        end if

        Redim oACES(lNumValidACEs-1)
        lNumValidACEs = 0
        for each oACE in oWin32SD.DACL
            if oACE.Trustee.SIDString <> oTrustee.SIDString Then
                set oACEs(lNumValidACEs) = oConnection.Get("Win32_ACE").SpawnInstance_
                oACEs(lNumValidACEs).AccessMask = oACE.AccessMask
                oACEs(lNumValidACEs).ACEFlags = oACE.ACEFlags
                oACEs(lNumValidACEs).ACEType = oACE.ACEType
                oACEs(lNumValidACEs).Trustee = oACE.Trustee
                lNumValidACEs = lNumValidACEs + 1
            end if
        next
       
        ' Update the DACL
        oWin32SD.Properties_.Item("DACL") = oACEs
        Dbg DBG_STD, "RemoveACEFromDACL: After removing ACE " & oWin32SD.GetObjectText_
        Dbg DBG_STD, "RemoveACEFromDACL: RC=" & err.number

        Set oACE = Nothing

    End Function ' RemoveACEFromDACL

    ' ********************************************************************
    ' * AddACEToDACL: Rebuilds the DACL with an ACE of the trustee missing 
    ' * Returns ERROR_ALREADY_PRESENT if it's already in there
    ' ********************************************************************
    Function AddACEToDACL(ByRef oWin32SD, oConnection, oTrustee, bWarnIfExistsAlready)

        Dim lMaxACE     ' Number of ACEs in the DACL
        Dim arrDACL     ' Array of DACLs to set in the win32_SecurityDescriptor
        Dim i           ' Lopp control variable

        On error resume next

        Dbg DBG_STD, "AddAceToDACL: SID=" & oTrustee.SIDString

        ' HARD QUIT: Don't allow any of the well known built in SIDs
        ' It looks like it's a bug by not including SID_HYPERV_ADMINISTRATORS in this, but
        ' it's not. Reason being we call this function to fix Windows 8 client setup which
        ' doesn't set a DACL correctly, and the ACE is for Hyper-V Administrators.
        if (lcase(oTrustee.SIDString) = lcase(SID_EVERYONE)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_ANONYMOUS)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_BUILTIN_ADMINISTRATORS)) or _
           (lcase(oTrustee.SIDString) = lcase(SID_DISTRIBUTED_COM_USERS)) Then
            Error "HARD BLOCK HERE. Not manipulating that group!!!"
            wscript.quit
        end if

        ' Does an entry already exist (MINOR BUGBUG, Long standing - Should check for deny's explicitly)
        for i = lbound(oWin32SD.DACL) to ubound(oWin32SD.DACL)
            if lcase(oTrustee.SIDString) = lcase(oWin32SD.DACL(i).Trustee.SIDString) Then
                Dbg DBG_STD, "AddAceToDACL() - ACE already exists, not adding"
                if bWarnIfExistsAlready then wscript.echo "WARN: An ACL already exists for this account."
                AddAceToDACL = ERROR_ALREADY_PRESENT
                exit function
            end if
        next

        ' Get the current DACL locally and resize it to add a new ACE to it. 
        lMaxACE = UBound(oWin32SD.DACL) + 1
        Dbg DBG_STD, "AddAceToDACL: Resizing ACE Count to " & lMaxACE
        arrDACL = oWin32SD.DACL
        Redim Preserve arrDACL(lMaxACE)

        ' Create an object instance an populate it.
        set arrDACL(lMaxACE) = oConnection.Get("win32_ACE").SpawnInstance_
        arrDACL(lMaxACE).Properties_.Item("AccessMask") = WBEM_ENABLE + WBEM_REMOTE_ACCESS
        arrDACL(lMaxACE).Properties_.Item("AceFlags")   = ADS_ACEFLAG_INHERIT_ACE + _ 
                                                          ADS_ACEFLAG_NO_PROPAGATE_INHERIT_ACE
        arrDACL(lMaxACE).Properties_.Item("AceType")    = ADS_ACETYPE_ACCESS_ALLOWED
        arrDACL(lMaxACE).Properties_.Item("Trustee")    = oTrustee

        ' Set the DACL back in the security descriptor
        oWin32SD.Properties_.Item("DACL") = arrDACL

        if (0<>err.number) Then
            Error "AddACEToDACL: Failed to Set DACL!!!" & err.description
            wscript.quit
        else
            Dbg DBG_STD, "AddAceToDACL: RC=0"
        end if

        AddACEToDACL = NO_ERROR 

    End Function ' AddACEToDACL


    ' ********************************************************************
    ' * GetWin32SD: Gets a Win32_SecurityDescriptor object
    ' ********************************************************************
    Function GetWin32SD(oConnection, ByRef oWin32SD)

        Dim oSystemSecurity    ' Object for __SystemSecurity
        Dim lReturn            ' Function return value
        Dim outParams          ' output Parameters from GetSD WMI Call
        Dim oWin32SDHelper     ' Helper utility for converting binary SDDL

        On error resume next

        lReturn = NO_ERROR
        set oWin32SD = nothing
        set oSystemSecurity = Nothing
        set outParams = Nothing
        set oWin32SDHelper = Nothing

        if (NO_ERROR = lReturn) Then               
            Dbg DBG_STD, "GetWin32SD(): Get __SystemSecurity"
            Set oSystemSecurity = oConnection.Get("__SystemSecurity=@")
            if (err.number) then
                Error "Failed to get system security for namespace"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Fixed in 0.6. 518091. GetSecurityDescriptor has a problem when there unknown SIDs
        ' You can get this by having a domain joined box, adding a domain user, then moving the
        ' box to a workgroup. 

        'if (NO_ERROR = lReturn) Then
        '    set outParams = oSystemSecurity.ExecMethod_("GetSecurityDescriptor")
        '    if (outParams is nothing) or (err.number) Then
        '        lReturn = -1
        '        Error "Failed to call GetSecurityDescriptor" 
        '        if not(outParams is nothing) then Dbg DBG_STD, "GetSeurityDesecriptor ReturnValue=" & outParams.ReturnValue 
        '    else
        '        set oWin32SD = outParams.Descriptor
        '        Dbg DBG_STD, "Current SecurityDescriptor Details:" & oWin32SD.GetObjectText_
        '    end if
        'end if

        ' Fixed Code for workaround. Use GetSD then convert binary SDDL
        if (NO_ERROR = lReturn) Then
            set outParams = oSystemSecurity.ExecMethod_("GetSD")
            if (outParams is nothing) or (err.number) Then
                lReturn = -1
                Error "Failed to call GetSD" 
                if not(outParams is nothing) then Dbg DBG_STD, "GetSD ReturnValue=" & outParams.ReturnValue 
            else
                set oWin32SD = outParams.Descriptor
                Dbg DBG_STD, "Current SD (Binary Details:" & outParams.GetObjectText_
            end if
        end if

        ' Instantiate a Win32_SecurityDescriptorHelper object
        if (NO_ERROR = lReturn) Then
            err.clear
            set oWin32SDHelper = GetObject("winmgmts:root\cimv2:Win32_SecurityDescriptorHelper")
            if (err.number) or (oWin32SDHelper is nothing) then
                Error "Failed to instantiate Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Do the conversion
        if (NO_ERROR = lReturn) Then
            set oWin32SD = Nothing
            err.clear
            oWin32SDHelper.BinarySDToWin32SD outparams.SD, oWin32SD
            if (err.number) or (oWin32SDHelper is nothing) then
                Error "Failed to convert binary SDDL using Win32_SecurityDescriptorHelper"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            else
                Dbg DBG_STD, "Current Security Descriptor (converted):" & oWin32SD.GetObjectText_
            end if
        end if 

        Dbg DBG_STD, "GetWin32SD(): Exit RC=" & lReturn

        GetWin32SD = lReturn
        set oSystemSecurity = Nothing
        set outParams = Nothing
        set oWin32SDHelper = Nothing

    End Function ' GetWin32SD

    ' ********************************************************************
    ' * SetWin32SD: Sets a Win32_SecurityDescriptor object for a namespace
    ' ********************************************************************
    Function SetWin32SD(szNameSpace, oWin32SD, oConnection)

        Dim lReturn            ' Function return value
        Dim oSystemSecurity    ' Object for __SystemSecurity
        Dim inParams           ' Input parameters to SetSecurityDescriptor
        Dim outParams          ' Output parameters from SetSecurityDescriptor

        On error resume next


        set oSystemSecurity = Nothing
        set inParams = Nothing
        set outParams = Nothing
        lReturn = NO_ERROR

        if (NO_ERROR = lReturn) Then               
            Dbg DBG_STD, "SetWin32SD(): Get __SystemSecurity"
            Set oSystemSecurity = oConnection.Get("__SystemSecurity=@")
            if (err.number) then
                Error "Failed to get system security for namespace " & szNameSpace
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "SetWin32SD(): Spawning inParams"
            set inParams = oSystemSecurity.methods_("SetSecurityDescriptor").inParameters.SpawnInstance_
            if (err.number) or (inParams is nothing) Then
                Error "Failed to spawn inParams for SetSecurityDescriptor"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if
 
        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "SetWin32SD(): Setting inParams for call"
            inParams.Descriptor = oWin32SD
            inParams.Descriptor.ControlFlags = SE_DACL_PRESENT
            if (err.number) Then
                Error "Failed to set inParams for SetSecurityDescriptor"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            Dbg DBG_STD, "SetWin32SD(): Calling SetSecurityDescriptor"
            Set outParams = oSystemSecurity.ExecMethod_("SetSecurityDescriptor", inParams)
            if (err.number) or (outParams is nothing) Then
                Error "Failed to call SetSecurityDescriptor"
                Error "Error: " & err.description & " " & err.number
                lReturn = -1
            end if

        end if

        ' Special case way of validating return code from method invocation 
        if (NO_ERROR = lReturn) Then
            lReturn = outParams.ReturnValue
            if (NO_ERROR <> lReturn) Then
                Error "Call to SetSecurityDescriptor failed"
                Error "Error RC=" & lReturn
            end if
        end if
          
        Dbg DBG_STD, "SetWin32SD(): Exit " & lReturn
        Dbg DBG_EXTRA, "SetWin32SD: New SD " & oWin32SD.GetObjectText_
        if (NO_ERROR = lReturn) Then wscript.echo "INFO: Security update applied to " & szNameSpace & " namespace"

        set oSystemSecurity = Nothing
        set inParams = Nothing
        set outParams = Nothing

        SetWin32SD = lReturn

    End Function 'SetSD


    ' ********************************************************************
    ' * GetTrustee: Gets a Trustee for a user or group plus domain
    ' ********************************************************************
    Function GetTrustee(szInDomain, szUserOrGroup, ByRef oTrustee)

        Dim lReturn           ' Function return value tracking
        Dim oAccount          ' Either user or group
        Dim oAccountSID       ' SID object for the account (user or group) we are looking for
        Dim szDomain

        On error resume next    
        szDomain = szInDomain
        set oAccount = Nothing
        set oAccountSID = Nothing
        lReturn = NO_ERROR

        ' If we're in a workgroup and no domain was supplied by user, use the local computer name for the domain
        if 0=len(szDomain) Then
            if gbComputerIsWorkgroup Then szDomain = gszLocalComputerName                     
        end if

        Dbg DBG_STD, "GetTrustee(" & szDomain& "," & szUserOrGroup & ")"

        if (NO_ERROR = lReturn) Then
            Set oTrustee = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_Trustee").Spawninstance_
            if (oTrustee is nothing) or (err.number) Then
                lReturn = -1        
                Error "Failed to get Win32_Trustee"         
                Error "Error: " & err.description & " " & err.number 
            else
                Dbg DBG_STD, "GetTrustee(): OK Win32_Trustee"
            end if
        end if
        
        ' Try group and if that fails, try a user
        if (NO_ERROR = lReturn) Then

            ' Group
            Set oAccount = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_Group.Name='" & szUserOrGroup & "',Domain='" & szDomain &"'")

            if (ERROR_OBJECT_NOT_FOUND = err.number) Then 
                ' Group wasn't found
                Dbg DBG_STD, "GetTrustee(): Group not found, will try user"
                Err.clear

                ' Try Account
                Set oAccount = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_Account.Name='" & szUserOrGroup & "',Domain='" & szDomain &"'") 

                ' Can't do anything if group AND user not found
                if (ERROR_OBJECT_NOT_FOUND = err.number) Then
                    Error "GetTrustee Failed: " & szDomain & "\" & szUserOrGroup & " not found"
                    Error "If " & szDomain & " is a domain, you need to be connected to the domain for this to work"
                    lReturn = -1
                else
                    ' Some other catastrophic error occurred?
                    if (err.number) or (oAccount is nothing) Then
                        lReturn = -1
                        Error "Failure finding trustee " & err.description & " " & err.number
                    else
                        Dbg DBG_STD, "GetTrustee(): Found user or group OK"
                    end if
                end if
            else
                ' Some unexpected error getting the account by group?
                	 if (err.number) or (oAccount is nothing) Then
                    lReturn = -1 
                    Error "Failure finding trustee " & err.description & "  " & err.number 
                end if
            end if
        end if    


        ' Get the SID for the user or group we located above.        
        if (NO_ERROR = lReturn) Then
            set oAccountSID = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_SID.SID='" & oAccount.SID &"'")
            if (err.number) or (oAccountSID is Nothing) Then
                Error "Failure to get Account SID" 
                Error err.description & " " & err.number
            end if
        end if

        ' Create the Trustee Object
        if (NO_ERROR = lReturn) Then
            oTrustee.Name   = szUserOrGroup
            oTrustee.Domain = szDomain
            oTrustee.Properties_.Item("SID") = oAccountSid.BinaryRepresentation
            oTrustee.SIDString = oAccount.SID
            oTrustee.SIDLength = UBound(oAccountSID.BinaryRepresentation) + 1
            Dbg DBG_STD, "Trustee Instance We Built: " & oTrustee.GetObjectText_()
        end if

        set oAccount = Nothing
        set oAccountSID = Nothing
        GetTrustee = lReturn
        Dbg DBG_STD, "GetTrustee(): Exit RC=" & lReturn


   
    End Function ' GetTrustee


    ' ********************************************************************
    ' * GetTrusteeForSID: Gets a Trustee for a specified SID
    ' ********************************************************************

    Function GetTrusteeForSID(szSID, ByRef oTrustee)
        Dim lReturn           ' Function return value tracking
        Dim oAccountSID       ' SID object for the account we are looking for
        On error resume next    

        lReturn = NO_ERROR
        set oAccountSID = Nothing

        On error resume next

        Dbg DBG_STD, "GetTrusteeForSID(" & szSID &  ")"

        if (NO_ERROR = lReturn) Then
            Set oTrustee = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_Trustee").Spawninstance_
            if (oTrustee is nothing) or (err.number) Then
                lReturn = -1        
                Error "Failed to get Win32_Trustee"         
                Error "Error: " & err.description & " " & err.number 
            else
                Dbg DBG_STD, "DEBUG: GetTrusteeForSID(): OK Win32_Trustee"
            end if
        end if

        ' Get the Win32_SID object
        if (NO_ERROR = lReturn) Then
            set oAccountSID = GetObject("winmgmts:{impersonationlevel=impersonate}!//./root/cimv2:Win32_SID.SID='" & szSID &"'")
            if (err.number) or (oAccountSID is Nothing) Then
                Error "Failure to get Account SID" 
                Error err.description & " " & err.number
            end if
        end if
        
        ' Copy the stuff across
        if (NO_ERROR = lReturn) Then
            oTrustee.Name   = oAccountSID.AccountName
            oTrustee.Domain = oAccountSID.ReferencedDomainName
            oTrustee.SID = oAccountSID.BinaryRepresentation
            oTrustee.SIDString = oAccountSID.SID
            oTrustee.SIDLength = UBound(oAccountSID.BinaryRepresentation) + 1
            Dbg DBG_STD, "GetTrusteeForSID: Trustee Instance We Built: " & oTrustee.GetObjectText_()
        end if

        set oAccountSID = Nothing
        GetTrusteeForSID = lReturn
        Dbg DBG_STD, "GetTrustee-ForSID(): Exit RC=" & lReturn

    End Function ' GetTrusteeForSID


    ' ********************************************************************
    ' * Title: Displays title when invoked
    ' ********************************************************************
    Sub Title()

        On error resume next

                     '12345678901234567890123456789012345678901234567890123456789012345678901234567890
        wscript.echo " "
        wscript.echo "Hyper-V Remote Management Configuration & Checkup Utility"    
        wscript.echo "John Howard, Hyper-V Team, Microsoft Corporation."
        wscript.echo "http://blogs.technet.com/jhoward"
        wscript.echo "Version " & VERSION & " " & RELEASE_DATE
        wscript.echo "  "


    End Sub ' Title


    ' ********************************************************************
    ' * Usage: Displays Usage Help
    ' ********************************************************************
    Function Usage(szError)

        On error resume next

        wscript.echo "                                          "
        wscript.echo "Usage: cscript HVRemote.wsf [/mode:server|client] Operations [Options]"
        wscript.echo "" 
        wscript.echo "Server Mode "
        wscript.echo "    Operations: [/show [/target:clientname]                 |"
        wscript.echo "                 /add:domain\userorgroup    [/explicit]     | "
        wscript.echo "                 /remove:domain\userorgroup [/explicit]]"
        wscript.echo "                [/firewallhypervmgmt:enable | disable | None]"
        wscript.echo " "
        wscript.echo "    Options:    [/ns:none | cimv2 | virtualization** | virtualizationv2]"
        wscript.echo "                [/noazman]"
        wscript.echo "                [/nodcom]"
        wscript.echo "                [/roleassign:<Role Assignment in AZMan store>]"
        wscript.echo " "
        wscript.echo "Client Mode "
        wscript.echo "    Operations: [/show [/target:servername] | " 
        wscript.echo "                 /anondcom:grant|revoke | "
        wscript.echo "                 /firewallhypervclient:enable | disable | none]"
        wscript.echo "                 /da:enable | disable | none]"
        wscript.echo "                 /trace:on | off]"
        wscript.echo " "
        wscript.echo "All Modes "
        wscript.echo "    Options:    [/debug:standard|verbose]"
        wscript.echo "                [/noversioncheck]"
        wscript.echo "                [/override]"
        wscript.echo "               "
        wscript.echo "Parameter Guidance: "
        wscript.echo "    add:                  Grants permission to Hyper-V Management"
        wscript.echo "    remove:               Removes permission to Hyper-V Management"
        wscript.echo "    explicit:             Does not use 'Hyper-V Administrators' *" 
        wscript.echo "    firewallhypermgmt:    Opens/Closes required firewall ports "
        wscript.echo "    ns:                   Specifies WMI namespaces to manipulate"
        wscript.echo "    noazman:              Does not update AZMan **"
        wscript.echo "    nodcom:               Does not update Distributed COM Users group"
        wscript.echo "    roleassign:           Role assignment in AZMan to update **"
        wscript.echo "    show:                 Displays the configuration"
        wscript.echo "    target:               Remote computer name to test configuration"
        wscript.echo "    anondcom:             Configures Anonymous DCOM access"
        wscript.echo "    firewallhypervclient: Opens/Closes required firewall ports"
        wscript.echo "    da:                   Configures firewall for Direct Access"
        wscript.echo "    trace:                Configures client tracing"
        wscript.echo "    debug:                Shows debug tracing in output"
        wscript.echo "    noversioncheck:       Configure checking for newer version"
        wscript.echo "    override:             Use with caution!!"
        wscript.echo " "
        wscript.echo "    *  Windows Server 2012/Windows 8 and later release only"
        wscript.echo "    ** Windows Server 2012/Windows 8 and earlier releases only"
        wscript.echo " "
        wscript.echo "See online documentation for more information"
        wscript.echo " - " & gszLV_URL
        wscript.echo " - " & gszLV_BlogURL
        wscript.echo ""
 
         if Len(szError) Then
            Error szError
            wscript.quit -1
        end if

    End Function ' Usage


    ' ********************************************************************
    ' * GetGroupNameForSID : Gets *LOCALISED* group name for a SID
    ' ********************************************************************
    Function GetGroupNameForSID (szSID, ByRef szGroupName)

        Dim colAccounts       ' Collection of results from query
        Dim oGroup            ' To enumerate through collection
        Dim lReturn           ' Function return value    

        On error resume next

        lReturn = NO_ERROR
        szGroupName = ""
        set colAccounts = Nothing
        set oGroup = Nothing

        Dbg DBG_STD, "GetGroupNameForSID: " & szSID

        ' Do the query
        if (NO_ERROR = lReturn) Then
            Set colAccounts = GetObject("winmgmts://./root/cimv2").ExecQuery _
                                       ("Select Name from Win32_Group " & _
                                        "WHERE Domain = '.' " & _ 
                                        "AND SID = '" & szSID & "'") 
            if (err.number) or (colAccounts is nothing) Then
                Error "Failed to query for group with SID " & szSID
                Error err.description & " " & err.number
                lReturn = -1
            end if
        end if


        ' Must get one and one item only back
        if (NO_ERROR = lReturn) Then
            if colAccounts.Count <> 1 then
                Error "Error: Query for group with SID " & szSID & " got " & colAccounts.Count & " hits"
                lReturn = -1
            end if
        end if
                            

        if (NO_ERROR = lReturn) Then
           For Each oGroup in colAccounts 
               szGroupName = oGroup.Name
           next
        end if

        Dbg DBG_STD, "GetGroupNameForSID: RC=" & lReturn & " GroupName=" & szGroupName

        set colAccounts = Nothing
        set oGroup = Nothing

        GetGroupNameForSID = lReturn

    End Function ' GetGroupNameForSID

    ' ********************************************************************
    ' * IsLocalGroup : Determines if a given SID is a local group
    ' *                Helper function introduced in 1.03
    ' ********************************************************************
    Function IsLocalGroup (szSID, ByRef bIsLocalGroup)

        Dim colAccounts       ' Collection of results from query
        Dim oGroup            ' To enumerate through collection
        Dim lReturn           ' Function return value    

        On error resume next

        lReturn = NO_ERROR
        bIsLocalGroup = False
        set colAccounts = Nothing
        set oGroup = Nothing

        Dbg DBG_STD, "IsLocalGroup: " & szSID

        ' Do the query
        if (NO_ERROR = lReturn) Then
            Set colAccounts = GetObject("winmgmts://./root/cimv2").ExecQuery _
                                       ("Select * from Win32_Group " & _
                                        "WHERE SID = '" & szSID & "'" & _
                                        "AND LocalAccount = TRUE") 

            if (err.number) or (colAccounts is nothing) Then
                Error "Failed to query for group with SID " & szSID
                Error err.description & " " & err.number
                lReturn = -1
            end if
        end if

        ' Must not get more than one item back
        if (NO_ERROR = lReturn) Then
            select case colAccounts.Count
                case 0: bIsLocalGroup = False
                case 1: bIsLocalGroup = True
                case else: 
                     bIsLocalGroup = False
                     Error "Error: Query for group with SID " & szSID & " got " & colAccounts.Count & " hits"
                    lReturn = -1
            end select
        end if

        Dbg DBG_STD, "IsLocalGroup: RC=" & lReturn & " IsLocalGroup=" & bIsLocalGroup

        set colAccounts = Nothing
        set oGroup = Nothing

        IsLocalGroup = lReturn

    End Function ' IsLocalGroup



    ' ********************************************************************
    ' * RunShellCmd: What it says on the tin  '1.03 Consolidation of functions
    ' ********************************************************************
    Function RunShellCmd(szCmd, szTitle, bPrintOutput, byref szOutput,bIgnoreExitCode)
   
        Dim lReturn
        Dim oShell
        Dim oExec
        Dim szTemp
        Dim lCount
        
        lReturn = NO_ERROR
        set oShell = Nothing
        set oExec = Nothing
        lCount = 0
        szOutput = ""

        On error resume next

        if len(szTitle) Then
            wscript.echo " "
            wscript.echo "-------------------------------------------------------------------------------"
            wscript.echo szTitle
            wscript.echo "-------------------------------------------------------------------------------"
            wscript.echo " "
        end if

        if (NO_ERROR = lReturn) Then
            Set oShell = CreateObject("WScript.Shell")
            Set oExec = oShell.Exec(szCmd)

            ' Drain Stdout
            Do While (oExec.Status = 0) and (lCount < 100) ' No more than 10 seconds
                WScript.Sleep 100
                ' Bizarre. Looks like it blocks unless we undrain stdout
                if not oExec.StdOut.AtEndOfStream then szTemp = szTemp & oExec.StdOut.ReadAll
                lCount = lCount + 1
            Loop
            if not oExec.StdOut.AtEndOfStream then szTemp = szTemp & oExec.StdOut.ReadAll    

            ' Drain stderr
            lCount = 0
            Do While (oExec.Status = 0) and (lCount < 100) ' No more than 10 seconds
                WScript.Sleep 100
                ' Bizarre. Looks like it blocks unless we undrain stdout
                if not oExec.StdOut.AtEndOfStream then szTemp = szTemp & oExec.StdErr.ReadAll
                lCount = lCount + 1
            Loop
            if not oExec.StdErr.AtEndOfStream then szTemp = szTemp & oExec.StdErr.ReadAll    

            if (0 <> oExec.ExitCode) Then
                if not bIgnoreExitCode then
                    'Error "Failed to run " & szCmd
                    lReturn = -1
                    lReturn = oExec.ExitCode 
                end if
            else
                if bPrintOutput then wscript.echo szTemp
            end if
        end if


        set oShell = Nothing
        set oExec = Nothing
        szOutput = szTemp
        RunShellCmd = lReturn
     
    End Function ' RunShellCmd

    ' ********************************************************************
    ' * CheckElevation: Looks to see if you are running elevated
    ' ********************************************************************

    ' Note this is a glorious hack as I couldn't see an easy way to call 
    ' GetTokenInformation() from VBScript. But, along the way, discovered
    ' whoami /groups http://technet.microsoft.com/en-us/library/cc771299.aspx
    ' gives the Mandatory Label SID (works on all languages including Hyper-V
    ' server). S-1-16-12288 is High Mandatory Level
    Sub CheckElevation()

        Dim szOutput
        On error resume next

        Call RunShellCmd("whoami /groups","",False,szOutput,False)
        Dbg DBG_EXTRA, "CheckElevation() " & szOutput
        if instr(szOutput,"S-1-16-12288") Then glElevated = ELEVATION_YES
        if instr(szOutput,"S-1-16-8192") Then glElevated = ELEVATION_NO

    End Sub ' CheckElevation



    ' ********************************************************************
    ' * AddUserToGroup: Adds a user to a specified local group
    ' ********************************************************************
    Function AddUserToGroup(szDomainOfUserOrGroupToChange, szUserOrGroupToChange, szGroupName)

        Dim szTemp
        Dim szExec
        
        On error resume next
        Dbg DBG_STD, "AddUserToGroup: " & szDomainOfUserOrGroupToChange & "\" & szUserOrGroupToChange

        wscript.echo
        wscript.echo "Adding user to " & szGroupName & "..."

        ' Build the command to execute
        szExec = "net localgroup " & chr(34) & szGroupName & chr(34) & " " & chr(34) 
        if len(szDomainOfUserOrGroupToChange) Then szExec = szExec & szDomainOfUserOrGroupToChange & "\"
        szExec = szExec & szUserOrGroupToChange & chr(34) & " " & "/add"
        Dbg DBG_STD, "Exec: " & szExec
        if RunShellCmd(szExec,"",False,szTemp,False) Then
            if instr(szTemp,"1378") > 0 Then   ' Verified this even appears in Japanese locale so should be fairly safe.
                wscript.echo "WARN: " & szDomainOfUserOrGroupToChange & "\" & szUserOrGroupToChange & " is already in " & szGroupName
                wscript.echo "INFO: No action taken here"
            end if
        else
            wscript.echo "INFO: " & szDomainOfUserOrGroupToChange & " " & szUserOrGroupToChange & " added to " & szGroupName & " OK"
        end if
 
        AddUserToGroup = lReturn
           
    End Function 'AddUserToGroup


    ' ********************************************************************
    ' * RemoveUserFromGroup: Removes a user to a specified local group
    ' ********************************************************************
    Function RemoveUserFromGroup(szDomainOfUserOrGroupToChange, szUserOrGroupToChange, szGroupName)
   
        Dim szTemp
        Dim szExec
        
        On error resume next
        Dbg DBG_STD, "RemoveUserFromGroup: " & szDomainOfUserOrGroupToChange & "\" & szUserOrGroupToChange

        wscript.echo
        wscript.echo "Removing user from " & szGroupName & "..."

        ' Build the command to execute
        szExec = "net localgroup " & chr(34) & szGroupName & chr(34) & " " & chr(34) 
        if len(szDomainOfUserOrGroupToChange) Then szExec = szExec & szDomainOfUserOrGroupToChange & "\"
        szExec = szExec & szUserOrGroupToChange & chr(34) & " " & "/delete"
        Dbg DBG_STD, "Exec: " & szExec
        if RunShellCmd(szExec,"",False,szTemp,False) Then
            if instr(szTemp,"1377") > 0 Then   ' Verified this even appears in Japanese locale so should be fairly safe.
                wscript.echo "WARN: " & szDomainOfUserOrGroupToChange & "\" & szUserOrGroupToChange & " is not in " & szGroupName
                wscript.echo "INFO: No action taken here"
            end if
        else
            wscript.echo "INFO: " & szDomainOfUserOrGroupToChange & " " & szUserOrGroupToChange & " removed from " & szGroupName & " OK"
        end if

        RemoveUserFromGroup = lReturn
           
    End Function ' RemoveUserFromGroup


    ' ********************************************************************
    ' * EnumerateGroupMembers: Dumps users in a group
    ' ********************************************************************
    Function EnumerateGroupMembers (szGroupName, oWMI)


        Dim oShell                     ' For getting local computer name
        Dim szComputer                 ' Local computer name
        Dim lReturn                    ' Function return value
        Dim colGroupUser               ' Collection from win32_groupuser query
        Dim oGroupUser                 ' Enumerating colGroupUser
        Dim szQuery                    ' WMI Query
        Dim oUserAccount               ' To determine if account is disbaled, locked out or expired pwd.

        Set oShell = Nothing 
        szComputer = ""
        lReturn = NO_ERROR
        set colGroupUser = Nothing
        set oGroupUser = Nothing

        On error resume next

        wscript.echo " "

        Dbg DBG_STD, "EnumerateGroupMembers: Group=" & szGroupName
        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Contents of Group " & szGroupName
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo " "


        ' Need WScript.Shell to get the computer name environment variable
        if (NO_ERROR = lReturn) Then
            Set oShell = WScript.CreateObject("WScript.Shell") 
            if (err.number) or (oShell is nothing) Then
                Error "Failed to instantiate wscript.shell"
                Error err.description & " " & err.number
                lReturn = -1 
            end if
        end if

        ' Get the local computer name
        if (NO_ERROR = lReturn) Then
            szComputer = oShell.ExpandEnvironmentStrings("%COMPUTERNAME%")  
            if (err.number) or (0 = len(szComputer)) Then
                Error "Failed to get local computer name"
                Error err.description & " " & err.number
                lReturn = -1 
            end if
        end if


        ' One of the reasons this script only runs locally. Can't use . in this query.
        ' Get the list of group members
        if (NO_ERROR = lReturn) Then
            szQuery = "SELECT * FROM Win32_GroupUser WHERE " & _ 
                      "GroupComponent = ""Win32_Group.Domain='" & szComputer & _
                      "',Name='"& szGroupName &"'"""
            set colGroupUser = oWMI.ExecQuery(szQuery)
            if (err.number) or (colGroupUser is nothing) Then
                Error "Failed to query WMI for " & szQuery
                Error err.description & " " & err.number
                lReturn = -1 
            end if
        end if

        ' Enumerate them
        if (NO_ERROR = lReturn) Then
            if colGroupUser.Count = 0 then 
                wscript.echo "There are no members in " & szGroupName
            else
                wscript.echo colGroupUser.Count & " member(s) are in " & szGroupName
                wscript.echo
            end if
            for each oGroupUser in colGroupUser

              ' Bizarre - when computer account is in the group. Don't display it. Should work out why, but this works
              Dim oPartComponent
              set oPartComponent = Nothing
              set oPartComponent = oWMI.Get(oGroupUser.PartComponent)
              if not (oPartComponent is nothing) then


                wscript.echo "   - " & oWMI.Get(oGroupUser.PartComponent).Caption

                ' New for 0.4 Look for problematic user accounts
                if lcase(oWMI.Get(oGroupUser.PartComponent).Path_.Class) = "win32_useraccount" Then

                    'wscript.echo oWMI.Get(oGroupUser.PartComponent).GetObjectText_

                    set oUserAccount = oWMI.Get(oGroupUser.PartComponent)
                    if oUserAccount.Disabled = True then
                        wscript.echo "               ****WARN: This account is disabled"
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Found a disabled user account" & vbcrlf
                    end if
                    if oUserAccount.Lockout = True then
                        wscript.echo "               ****WARN: This account is Locked out"
                        glWarns = glWarns + 1
                        gszWarns = gszWarns & glWarns & ": Found a locked out user account" & vbcrlf
                    end if
                end if

                ' New for v1.03 Detect use of local groups in a domain environment
                if (not(gbComputerIsWorkGroup)) Then
                    if lcase(oWMI.Get(oGroupUser.PartComponent).Path_.Class) = "win32_group" Then
                        'wscript.echo oWMI.Get(oGroupUser.PartComponent).GetObjectText_
                        if CBool(oWMI.Get(oGroupUser.PartComponent).LocalAccount) Then
                           wscript.echo " "
                           wscript.echo "     *** WARN: " & oWMI.Get(oGroupUser.PartComponent).Caption & " is a local group."
                           wscript.echo "     ***  In a domain joined environment, you must either use domain groups"
                           wscript.echo "     ***  or add user accounts individually."
                           wscript.echo " "
                           glWarns = glWarns + 1
                           gszWarns = gszWarns & glWarns & ": Local group " & oWMI.Get(oGroupUser.PartComponent).Caption & " found in " & szGroupName & vbcrlf
                        end if
                    end if
                end if
              else
                wscript.echo "   - " & oGroupUser.PartComponent
              end if ' We have something to check
            next
        End if

        Set oShell = Nothing 
        set colGroupUser = Nothing
        set oGroupUser = Nothing                               
        set oUserAccount = Nothing

        EnumerateGroupMembers = lReturn
          
    End Function ' EnumerateGroupMembers

    ' ********************************************************************
    ' * ConnectNameSpace: Creates a connection to a WMI namespace
    ' ********************************************************************
    Function ConnectNameSpace(szNameSpace, szRemoteServer, ByRef oWbemServices, bSilent)

        Dim lReturn

        On error resume next

        lReturn = NO_ERROR
        Dbg DBG_STD, "ConnectNameSpace Entry: Namespace=" & szNameSpace 

        ' http://msdn.microsoft.com/en-us/library/aa393850(VS.85).aspx
        oSWbemLocator.Security_.AuthenticationLevel = wbemAuthenticationLevelDefault
        oSWbemLocator.Security_.ImpersonationLevel = wbemImpersonationLevelImpersonate


        if szRemoteServer = "" then
            set oWbemServices=oSWbemLocator.ConnectServer(".",szNameSpace)
        else
            set oWbemServices=oSWbemLocator.ConnectServer(szRemoteServer,szNameSpace)
        end if

        if (err.number) Then
            lReturn = -1
            if not(bSilent) then
                Error "Failed to connect to " & szNameSpace 
                Error "Error:     " & err.number & " " & err.description
                Error "Namespace: " & szNamespace
            end if
        else
            Dbg DBG_STD, "ConnectNameSpace Connected to " & szNamespace & " namespace "
        end if

        Dbg DBG_STD, "ConnectNameSpace Exit: Namespace=" & szNameSpace & ", RC=" & lReturn    
        ConnectNameSpace = lReturn

    end Function ' ConnectNameSpace


    ' ********************************************************************
    ' * AmILatestVersion: Version checker.
    ' ********************************************************************
    ' -1 Failure of some kind
    ' -2 Could not locate 
    '  1 No
    '  0 Yes
    Function AmILatestVersion(szURL)
   
   
       Dim oHTTP
       Dim lReturn
       Dim i              ' Iteration
       Dim aResponses     ' Array of version responses
       Dim arrTemp        ' Parsing each string we get
       Dim aLatest
       Dim aThisScript
       Dim bLatest
       bLatest = True


       on error resume next

       set oHTTP = Nothing
       lReturn = NO_ERROR

       if (NO_ERROR = lReturn) Then
           'set oHTTP = CreateObject("msxml2.xmlhttp")
           set oHTTP = CreateObject("msxml2.ServerXMLHTTP.3.0")  ' 0.7 to allow setTimeouts
           if (err.number) or (oHTTP is nothing) Then
               err.clear
               DBG DBG_EXTRA, "Failed to create msxml2.serverxmlhttp.3.0"
               lReturn = -1
           end if
       end if

       if (NO_ERROR = lReturn) Then
           oHTTP.setTimeouts 30*1000,30*1000,30*1000,8*1000 
           err.clear
           DBG DBG_EXTRA, SZURL
           oHTTP.Open "GET", szURL, false

           Dim szUA

           szUA = szUA & "Mozilla/4.0+(compatible;+" & VERSION  & ";"

           if (glClientServerMode=HVREMOTE_MODE_CLIENT) Then szUA = szUA & "+CLNT;"
           if (glClientServerMode=HVREMOTE_MODE_SERVER) Then szUA = szUA & "+SVR;"
           if len(gszRemoteComputerName) Then 
               szUA = szUA & "+TARG;"
               if (glClientServerMode = HVREMOTE_MODE_CLIENT) then szUA = szUA & "Pass" & glTestsPassed & ";"
           end if
           if (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_ADD) Then szUA = szUA & "+Add;"
           if (glServerOpAddRemoveUser=HVREMOTE_SERVEROP_ADDREMOVEUSER_REMOVE) Then szUA = szUA & "+Remove;"
           if (gbShowMode) Then szUA = szUA & "+SHOW;"
           if (gbComputerIsWorkgroup) Then szUA = szUA & "+WG;" else szUA = szUA & "+DOM;"
           if (gbIsSCVMM) Then szUA = szUA & "+SCVMM;"
           szUA = szUA & "+" & goLocalWin32OS.Version & "."
           if (glInstalledOS=HVREMOTE_INSTALLED_OS_SERVER) Then szUA=szUA & "Server" else szUA=szUA & "Client"
           if (gbIsRoleInstalled) Then szUA=szUA & ".HVRole"
           szUA = szUA+";"
           szUA = szUA & ")"
           oHTTP.setRequestHeader "User-Agent", szUA
           Dbg DBG_EXTRA, szUA
           if (err.number) Then
               err.clear
               DBG DBG_EXTRA, "Failed to get"
               lReturn = -1
           end if
       end if

       if (NO_ERROR = lReturn) Then
           oHTTP.Send             
           if (err.number) Then
                DBG DBG_EXTRA, "Failed to send"
               if err.number = &H80072EE2 then ' Timeout (new in 0.7)
                   DBG DBG_EXTRA, "timeout on send"
                   lReturn = -2
               else
                   lreturn = -1
               end if
               err.clear
           end if
       end if

       ' Response will be in format
       ' **START HVREMOTE VERSION** TAG Version=0.3 TAG Date=19th November 2008 
       ' TAG URL=http://code.msdn.microsoft.com/HVRemote 
       ' TAG BlogURL=http://blogs.technet.com/jhoward/something-like-this_blah.aspx **END HVREMOTE VERSION**
       ' No, not pretty, but wanted to make sure Community Server on my blog didn't start escaping characters 
       ' which would be the case if I put it in XML for example.

       ' 1.03 Moved to the HVRemote site on code.msdn.microsoft.com
       if (NO_ERROR = lReturn) Then
           Dbg DBG_EXTRA, oHTTP.ResponseText
           Dim iStart, iEnd
           iStart = instr(lCase(oHTTP.ResponseText),"start hvremote version")
           iEnd = instr(lCase(oHTTP.ResponseText),"end hvremote version")


           if (iStart > 0) and (iEnd > 0) Then

               Dim szTemp
               szTemp = mid(oHTTP.ResponseText, iStart+22, iEnd-iStart-25)
               szTemp = replace(szTemp,vbcrlf,"")
               szTemp = replace(szTemp,".EQ.","=")
               szTemp = replace(szTemp,".SLASH.","/")
               szTemp = replace(szTemp,".COLON.",":")
               szTemp = replace(szTemp,"&nbsp;"," ")
               szTemp = replace(szTemp,"CRLF",vbcrlf)
               aResponses = split(szTemp,"TAG")
           else
               Dbg DBG_EXTRA, "Not a valid version response:" & oHTTP.ResponseText
               lReturn = -2  
           end if
       end if
       


       if (NO_ERROR = lReturn) Then
           for i = 0 to ubound(aResponses)
               arrTemp = split(aResponses(i),"=")
               select case trim(lcase(arrTemp(0)))
                   case "version"  gszLV_Version    = Trim(arrTemp(1))
                   case "date"     gszLV_Date       = Trim(arrTemp(1))
                   case "url"      gszLV_URL        = Trim(arrTemp(1))
                   case "blogurl"  gszLV_BlogURL    = Trim(arrTemp(1))
                   case "type"     gszLV_Type       = Trim(arrTemp(1))
                   case "about"    gszLV_About      = Trim(arrTemp(1))
               end select               
           next
       end if

       ' Validate the version
       if (NO_ERROR = lReturn) and (len(gszLV_Version)) Then
           aLatest = split(gszLV_Version, ".")
           aThisScript = split(VERSION, ".")
           if ubound(aLatest) = 1 Then
               if CLng(aLatest(0)) > CLng(aThisScript(0)) Then
                   bLatest = False
                   Dbg DBG_Std, "Failed version check on major"
               else
                  if CLng(aLatest(0)) = CLng(aThisScript(0)) Then
                      if CLng(aLatest(1)) * 100 > CLng(aThisScript(1)) * 100 Then
                          bLatest = False
                      else
                          if CLng(aLatest(1)) * 100 < CLng(aThisScript(1)) * 100 Then
                              glWarns = glWarns + 1
                              gszWarns = gszWarns & glWarns & ": Running a dev version of HVRemote (Latest public release is " & gszLV_Version & ")" & vbcrlf & vbcrlf
                          else
                              wscript.echo "INFO: Are running the latest version"
                          end if
                      end if
                   else
                       glWarns = glWarns + 1
                       gszWarns = gszWarns & glWarns & ": Running a development version of HVRemote (Latest public release is " & gszLV_Version & ")" & vbcrlf & vbcrlf
                  end if
               end if
           end if


           if (not bLatest) Then

               wscript.echo " "
               wscript.echo "-------------------------------------------------------------------------------"
               wscript.echo "!!!!!!      There is a newer version of HVRemote available               !!!!!!"
               wscript.echo "-------------------------------------------------------------------------------"
               wscript.echo " "

               'wscript.echo "Latest Version: " & gszLV_Version
               'wscript.echo "Release Date:   " & gszLV_Date
               'wscript.echo "Location:       " & gszLV_URL

               'if len(gszLV_Type) then  wscript.echo "Type:           " & gszLV_Type
               'if len(gszLV_About) then wscript.echo vbcrlf & gszLV_About
               glWarns = glWarns + 1
               gszWarns = gszWarns & glWarns & ": There is a later version of HVRemote available:" & vbcrlf & vbcrlf

               gszWarns = gszWarns &  "   Latest Version: " & gszLV_Version &  "   [Running " & VERSION & "]" & vbcrlf
               gszWarns = gszWarns &  "   Release Date:   " & gszLV_Date & vbcrlf
               gszWarns = gszWarns &  "   Location:       " & gszLV_URL & vbcrlf

               if len(gszLV_Type) then  gszWarns = gszWarns &  "   Type:           " & gszLV_Type & vbcrlf
               if len(gszLV_About) then gszWarns = gszWarns &  vbcrlf & "   " & gszLV_About & vbcrlf

               lReturn = 1

          End if

       end if

              
       AmILatestVersion = lReturn

    End Function

    ' ********************************************************************
    ' * TestService: Is a specific service present or running?
    ' * lOption: SERVICE_TEST_PRESENT or SERVICE_TEST_RUNNING
    ' ********************************************************************
    Function TestService(oConnection,szServiceName,lOption)

        Dim colServices         ' Collection of services on the box
        Dim oService            ' For enumerating the services
        Dim lReturn             ' Function return value

        On error resume next

        lReturn = NO_ERROR
        TestService = False
        set colServices = Nothing
        set oService = Nothing

        if (NO_ERROR = lReturn) Then
            set colServices = oConnection.ExecQuery("select * from win32_service where name='" & szServiceName & "'")
            if err.number Then
                Error "Failed to query services"
                Error err.description & " " & err.number
                wscript.quit
            end if
        end if

        if (NO_ERROR = lReturn) and (lOption = SERVICE_TEST_PRESENT) Then
            if colServices.Count = 1 then 
                TestService = True
            end if
        end if

        if (NO_ERROR = lReturn) and (lOption = SERVICE_TEST_RUNNING) Then
            if colServices.Count = 1 Then
                for each oService in colServices
                    if oService.Started = False then
                        TestService = False
                    else
                        TestService = True
                    end if
                next
            end if
        end if

        set ColServices = Nothing
        set oService = Nothing

    End Function


    ' ********************************************************************
    ' * IsFirewallRunning: Is the windows firewall active?
    ' ********************************************************************
    Function IsFirewallRunning(oConnection)

        Dim lReturn             ' Function return value
        Dim oFWPolicy2          ' Object referencing the current firewall policy
        Dim CurrentProfiles     ' Current firewall policies
        Dim bRunning           

        On error resume next

        lReturn = NO_ERROR
        IsFirewallRunning = False
        set oFWPolicy2 = Nothing
        bRunning = False
    

        if (NO_ERROR = lReturn) Then
            bRunning = TestService(oWbemServicesCIMv2,"MPSSvc", SERVICE_TEST_RUNNING)
            if (bRunning = False) Then
               wscript.echo " "
               wscript.echo "WARN: The Windows Firewall is not running."
               wscript.echo "      Not all functionality of HVRemote will be available."
               wscript.echo "      Use 'net start mpssvc' to start it!"
               wscript.echo " "
               glWarns = glWarns + 1
               gszWarns = gszWarns & glWarns & ": Firewall is not running" & vbcrlf
            end if
        end if

        ' Even if the service is running, it could still be disabled.
        if (NO_ERROR = lReturn) and (bRunning = True) Then
            Set oFWPolicy2 = CreateObject("HNetCfg.FwPolicy2")
            if (err.number) or (oFWPolicy2 is nothing) Then
                Error "Failed to create HNetCfg.FwPolicy2 object"
                Error err.description & " " & lReturn
                lReturn = -1
            end if
        end if

        ' See http://msdn.microsoft.com/en-us/library/aa366328(VS.85).aspx
        if (NO_ERROR = lReturn) and (bRunning = True) Then
            CurrentProfiles = ofwPolicy2.CurrentProfileTypes
            if ( CurrentProfiles AND NET_FW_PROFILE2_DOMAIN )  then if ofwPolicy2.FirewallEnabled(NET_FW_PROFILE2_DOMAIN) = False then bRunning = False
            if ( CurrentProfiles AND NET_FW_PROFILE2_PRIVATE ) then if ofwPolicy2.FirewallEnabled(NET_FW_PROFILE2_PRIVATE) = False then bRunning = False
            if ( CurrentProfiles AND NET_FW_PROFILE2_PUBLIC )  then if ofwPolicy2.FirewallEnabled(NET_FW_PROFILE2_PUBLIC) = False then bRunning = False
            if bRunning = False then 
                wscript.echo " "
                wscript.echo "WARN: The Windows firewall is not active in one or more active profiles."
                wscript.echo "      Not all functionality of HVRemote will be available."
                ' 0.7: KB947709 - netsh firewall deprecated in Windows 7/R2
                if (glOSRelease < WIN_7) Then
                    wscript.echo "      Use 'netsh firewall set opmode enable' to turn it on!"
                else
                    wscript.echo "      Use 'netsh advfirewall set currentprofile state on' to turn it on!"
                end if
                wscript.echo " "
                glWarns = glWarns + 1 
                gszWarns = gszWarns & glWarns & ": Firewall is not active" & vbcrlf
           end if
        end if 

        set oFWPolicy2 = Nothing
        IsFirewallRunning = bRunning

    End Function ' IsFirewallRunning


    ' ********************************************************************
    ' * GetPingFailureReason: See MSDN for win32_pingstatus
    ' ********************************************************************
    Function GetPingFailureReason(lStatus)
        GetPingFailureReason = ""
        select case lStatus
            case 11001: GetPingFailureReason = "Buffer too small"
            case 11002: GetPingFailureReason = "Destination net unreachable"
            case 11003: GetPingFailureReason = "Destination host unreachable"
            case 11004: GetPingFailureReason = "Destination protocol unreachable"
            case 11005: GetPingFailureReason = "Destination port unreachable"
            case 11006: GetPingFailureReason = "No resources"
            case 11007: GetPingFailureReason = "Bad option"
            case 11008: GetPingFailureReason = "Hardware error"
            case 11009: GetPingFailureReason = "Packet too big"
            case 11010: GetPingFailureReason = "Request timed out"
            case 11011: GetPingFailureReason = "Bad request"
            case 11012: GetPingFailureReason = "Bad route"
            case 11013: GetPingFailureReason = "TTL expired transit"
            case 11014: GetPingFailureReason = "TTL expired reassembly"
            case 11015: GetPingFailureReason = "Parameter problem"
            case 11016: GetPingFailureReason = "Source quench"
            case 11017: GetPingFailureReason = "Option too big"
            case 11018: GetPingFailureReason = "Bad destination"
            case 11032: GetPingFailureReason = "Negotiating IPSec"
            case 11050: GetPingFailureReason = "General Failure"
        end select
    End Function

    ' ********************************************************************
    ' * DoWMIPing: Does a ping using WMI. Neater than ping.exe
    ' ********************************************************************
    Function DoWMIPing(szComputerName, oConnection, byref bRecommendRegularPing)

        Dim lReturn
        Dim oPings
        Dim oPing
        Dim szFailureReason



        lReturn = NO_ERROR
        set oPings = Nothing
        set oPing = Nothing
        szFailureReason = ""
        bRecommendRegularPing = False

        On error resume next
            
        set oPings = oConnection.ExecQuery("select * from win32_pingstatus where address='" & szComputerName & "' and ResolveAddressNames=TRUE")        
        for each oPing in oPings
            Dbg DBG_EXTRA, oPing.GetObjectText_
            if oPing.PrimaryAddressResolutionStatus <> 0 then 
                if oPing.PrimaryAddressResolutionStatus = 11001 then
                    szFailureReason = "Host not found"
                else
                    szFailureReason = GetPingFailureReason(oPing.PrimaryAddressResolutionStatus)
                end if

                ' All these mean we couldn't resolve the remote computer and hence are errors
                Error "Failed to ping " & szComputerName
                Error szFailureReason
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Failed to ping " & szComputerName & ": " & szFailureReason & vbcrlf
                wscript.echo " "
                wscript.echo "     You may need to fix DNS or add an entry to your hosts file located "
                wscript.echo "     at \windows\system32\drivers\etc with the correct IP address."
                wscript.echo " "
                lReturn = -1

             else
                'PrimaryAddressResolutionStatus is OK, so remote machine was located
                if IsNull(oPing.StatusCode) Then
                    ' This should never happen if PrimaryAddressResolutionStatus is populated.
                    szFailureReason = "No idea!!!! This is an unexpected error. Please report this full output using /debug:verbose option"
                    Error "Failed to ping " & szComputerName
                    Error szFailureReason
                    glWarns = glWarns + 1
                    gszWarns = gszWarns & glWarns & ": Failed to ping " & szComputerName & ": " & szFailureReason & vbcrlf
                    lReturn = -1
                 else
                     if oPing.StatusCode <> 0 then
                         szFailureReason = GetPingFailureReason(oPing.StatusCode)
                         ' Could just be a timeout
                         if oPing.StatusCode = 11010 then
                             wscript.echo " "
                             wscript.echo "     Ping to " & szComputerName & " timed out " & vbcrlf
                             wscript.echo "     This is fine, it could just be the firewall. Nothing to see here...."
                             wscript.echo "     However, a regular ping will be done to see if name resolution is working."
                             wscript.echo " "
                             bRecommendRegularPing = True
                         else
                             Error "Failed to ping " & szComputerName
                             Error szFailureReason
                             ' We know box was resolved, so not a DNS or hosts issue. 
                             glWarns = glWarns + 1
                             gszWarns = gszWarns & glWarns & ": Failed to ping " & szComputerName & ": " & szFailureReason & vbcrlf
                             lReturn = -1
                         end if
                     else
                         wscript.echo "     PASS - Server found"
                         if oPing.PrimaryAddressResolutionStatus = 0 then
                              wscript.echo "          - Protocol Address:             " & oPing.ProtocolAddress
                              wscript.echo "          - Protocol Address resolved:    " & oPing.ProtocolAddressResolved
                              wscript.echo " "
                              if oPing.ProtocolAddress = oPing.ProtocolAddressResolved then
                                 wscript.echo "     The name could not be resolved using WMI. A regular ping will be done"
                                 wscript.echo "     to see if name resolution is working. This is not a sign of an issue."
                                 wscript.echo " "
                                 bRecommendRegularPing = True
                              end if
                         end if
                     end if 'oPing.StatusCode<>0
                 end if 'IsNull(oPing.StatusCode)
             end if 'oPing.PrimaryAddressResolutionStatus = 11001
         next

         DoWMIPing = lReturn

    End Function

    ' ********************************************************************
    ' * DoRegularPingTest: Easier to have it once and called many times
    ' ********************************************************************

    Function DoRegularPingTest(lTestNumber,szComputerName,IPVersion)

        Dim szTemp
        Dim lReturn
        szTemp = ""
        lReturn = NO_ERROR

        On error resume next


        wscript.echo lTestNumber & ": - Ping " & szComputerName & " using IPv" & IPVersion
        lReturn = RunShellCmd("ping -" & IPVersion & " -n 1 " & szComputerName,"", False, szTemp,True)
        wscript.echo ""
        wscript.echo "     A timeout is OK, but if you get an error that " & szComputerName 
        wscript.echo "     could not be found, you need to fix DNS or edit"
        wscript.echo "     \windows\system32\drivers\etc\hosts."
        wscript.echo ""
        wscript.echo Indent(szTemp,5)
        wscript.echo ""
        wscript.echo ""
        DoRegularPingTest = lReturn

    End Function


    ' ********************************************************************
    ' * ShowRemoteMachineIPCOnfiguration: What it says on the tin.
    ' * Note that server connecting back to client may legitimately not
    ' * have permission, so bail out gracefully in that case.
    ' ********************************************************************
    Function ShowRemoteMachineIPConfiguration()

        Dim lReturn
        Dim ColResult
        DIm i
        Dim szTemp
        Dim lNetNumber
        Dim oResult

        Set ColResult = Nothing
        lReturn = NO_ERROR

        On Error Resume Next

        ' IP Addresses http://technet.microsoft.com/en-us/library/ee692586.aspx
        err.clear
        set ColResult = Nothing
        set ColResult = goRemoteCIMv2.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True")

        if (err.number) then

            ' Note we are silent if this is from a server to a client and the server may well not have permission.
            if (glClientServerMode = HVREMOTE_MODE_CLIENT) Then

                wscript.echo "     FAIL - Could not query remote machine"
                wscript.echo ""
                wscript.echo "     - Have you run hvremote /add:user or hvremote /add:domain\user"
                wscript.echo "       on the server to grant access?"
                wscript.echo ""
                wscript.echo "     - Are you sure the remote machine name has been entered correctly?"
                wscript.echo ""
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot perform CIMv2 WMI query on remote machine" & vbcrlf
                lReturn = -1  
            end if
        else

            wscript.echo "     PASS - Found one or more network adapters"
            lNetNumber = 0
            For Each oResult in colResult
               lNetNumber = lNetNumber + 1
               Dbg DBG_EXTRA, oResult.GetObjectText_

               wscript.echo " "
               wscript.echo "     Network adapter " & lNetNumber & " of " & colResult.Count
               wscript.echo "       - " & oResult.Description
               if len(oResult.DNSHostName) Then wscript.echo "       - Host Name:" & oResult.DNSHostName
               if oResult.DHCPEnabled then wscript.echo "       - Configured by DHCP"

               szTemp = "       - IP Addresses:"
               if uBound(oResult.IPAddress) then 
                   for i = 0 to ubound(oResult.IPAddress)
                       szTemp = szTemp & " " & oResult.IPAddress(i) 
                   next
                   wscript.echo szTemp
               end if

               szTemp = "       - IP Subnets:"
               if uBound(oResult.IPSubnet) then 
                   for i = 0 to ubound(oResult.IPSubnet)
                       szTemp = szTemp & " " & oResult.IPSubnet(i) 
                   next
                   wscript.echo szTemp
               end if


               wscript.echo ""
            Next
        end if
        ShowRemoteMachineIPConfiguration = lReturn

    End Function  ' ShowRemoteMachineIPConfiguration

    ' ********************************************************************
    ' * ShowRemoteMachineCOmputerConfiguration: Common part of testing
    ' * between machines.
    ' ********************************************************************
    Sub ShowRemoteMachineComputerConfiguration()


        wscript.echo "     PASS - Queries succeeded"
        wscript.echo " "        
        wscript.echo "     - Name: " & lcase(goRemoteWin32CS.Name)

        if Not IsNull(goRemoteWin32CS.Workgroup) Then 
            wscript.echo "     - Workgroup: " & goRemoteWin32CS.Workgroup
        else
            wscript.echo "     - Domain: " & goRemoteWin32CS.Domain
        end if

        wscript.echo "     - OS: " & goRemoteWin32OS.Version & " " & goRemoteWin32OS.OSArchitecture & " " & goRemoteWin32OS.Caption

        if goRemoteWin32OS.ProductType = 1 Then 
            wscript.echo "     - OS Type: Client"
        else
            wscript.echo "     - OS Type: Server"
        end if

        wscript.echo ""
    End Sub

    ' ********************************************************************
    ' * TestCallsToServer: Various tests for client to server connectivity
    ' ********************************************************************
    Function TestCallsToServer(oConnection)

        Dim lReturn			' Function return value
        Dim szTemp			' For string building
        Dim colResult			' Object collection from WMI
        Dim oResult                     ' For iterating through collection
        Dim oSink			' Async callback sync
        Dim oSinkv2			' Async callback sync (for the v2 namespace)
        Dim lTestNumber			' When counting tests
        DIm bRecommendRegularPing	' Obvious
        Dim lNetNumber                  ' Loop iteration
        Dim i                           ' Loop iteration

 
        set colResult = Nothing
        set oSink = Nothing
        set oSinkv2 = Nothing
        set oResult = Nothing
        lReturn = NO_ERROR
        szTemp = ""
        lTestNumber = 1
        bRecommendRegularPing = False

        On error resume next

        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Testing connectivity to server:" & gszRemoteComputerName 
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo " "


        ' Test 1: Query remote machine for information. This is useful when people only send me output
        ' from one the client, it tells me a little about the server config
        if (NO_ERROR = lReturn) and (not goRemoteCIMv2 is nothing) Then
            wscript.echo lTestNumber & ": - Remote computer network configuration"
            ShowRemoteMachineIPConfiguration()
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if ' Remote Server Network Configuration


        ' Test 2: Information about remote computer configuration
        if (NO_ERROR = lReturn) and not(goRemoteWin32CS is nothing) and not(goRemoteWin32OS is nothing) Then
            wscript.echo lTestNumber & ": - Remote computer general information"
            ShowRemoteMachineComputerConfiguration()
            glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
        end if


        ' 1.03 Test 3: WMI style ping & nslookup combined
        if (NO_ERROR = lReturn) Then
            wscript.echo lTestNumber & ": - Ping and resolve name of remote computer"
            lReturn = DoWMIPing (gszRemoteComputerName,oConnection,bRecommendRegularPing)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if ' WMI style ping

        ' Test 4: (Optional) If name resolution failed in test 1, do a regular IPv4 ping just so I can see the output
        ' when people tell me it's not working
        if (NO_ERROR = lReturn) and (bRecommendRegularPing) Then
            lReturn = DoRegularPingTest(lTestNumber,gszRemoteComputerName, 4)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if

        ' Test 5: (Optional) If name resolution failed in test 1, do a regular IPv6 ping just so I can see the output
        ' when people tell me it's not working
        if (NO_ERROR = lReturn) and (bRecommendRegularPing) Then
            lReturn = DoRegularPingTest(lTestNumber,gszRemoteComputerName, 6)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if

        ' Test 6: Connection to CIMv2 namespace. '1.03 We already have a connection for other reasons, but didn't
        ' give any output, just failed silently if we couldn't connect.
        if (NO_ERROR = lReturn) Then
            wscript.echo lTestNumber & ": - Connect to root\cimv2 WMI namespace"
            if (goRemoteCIMv2 is Nothing) Then
                wscript.echo "     FAIL - Was unable to connect. Diagnosis steps:"
                wscript.echo ""
                wscript.echo "     - Have you run hvremote /add:user or hvremote /add:domain\user"
                wscript.echo "       on " & gszRemoteComputerName & " to grant access?"
                wscript.echo ""
                wscript.echo "     - Are you sure the server name '" & gszRemoteComputerName & "' is correct?"
                wscript.echo ""
                wscript.echo "     - Did you use cmdkey to set credentials to the remote machine if needed?"

                '1.03 This appears fixed in Windows 8

                if (glRemoteOSRelease < WIN_8) and (glRemoteOSRelease <> WIN_UNKNOWN) Then
                    wscript.echo ""
                    wscript.echo "     - Did you restart " & gszRemoteComputerName & " after running hvremote /add for "
                    wscript.echo "       the very first time? (Subsequent adds, no restart needed.)"
                end if

                wscript.echo ""
                wscript.echo "     - Is DNS operating correctly and was " & gszRemoteComputerName & " found?"
                wscript.echo "       Look at previous tests to verify that the IP address"
                wscript.echo "       matches the output of 'ipconfig /all' when run on"
                wscript.echo "       " & gszRemoteComputerName & ". If you do not have a DNS infrastructure, "
                wscript.echo "       edit \windows\system32\drivers\etc on " & gszLocalComputerName 
                wscript.echo "       to add an entry for " & gszRemoteComputerName & "."
 
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot connect to root\cimv2 on " & gszRemoteComputerName & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Connection established"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if
        
        ' Test 7: Connect to virtualization namespace. 1.03 We already have a connection for other reasons, but didn't
        ' give any output, just failed silently if we couldn't connect. 1.07 - note only if remote is Windows 8 or earlier
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease <= WIN_8) Then
            wscript.echo lTestNumber & ": - Connect to root\virtualization WMI namespace"
            if (goRemoteVirtualization is Nothing) Then
                wscript.echo "     FAIL - Connection attempt failed"
                wscript.echo ""
                wscript.echo "     - Have you run hvremote /add:user or hvremote /add:domain\user"
                wscript.echo "       on the remote computer to grant access?"
                wscript.echo ""
                wscript.echo "     - Are you sure the computer name has been entered correctly?"
                wscript.echo ""
                wscript.echo "     - Are you sure the remote computer is running Hyper-V?"
                wscript.echo ""
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot connect to root\virtualization on target server" & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Connection established"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if


        ' Test 8: Connect to virtualization\v2 namespace if remote machine is at least Windows 8
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease >= WIN_8) Then 
            wscript.echo lTestNumber & ": - Connect to root\virtualization\v2 WMI namespace"
            if (goRemoteVirtualizationv2 is nothing) Then
                wscript.echo "     FAIL - Connection attempt failed"
                wscript.echo ""
                wscript.echo "     - Have you run hvremote /add:user or hvremote /add:domain\user"
                wscript.echo "       on the remote computer to grant access?"
                wscript.echo ""
                wscript.echo "     - Are you sure the computer name has been entered correctly?"
                wscript.echo ""
                wscript.echo "     - Are you sure the remote computer is running Hyper-V?"
                wscript.echo ""
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot connect to root\virtualization\v2 on target computer" & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Connection established"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if


        ' Test 9: Simple query to root\cimv2 namespace
        ' 1.03 We don't need to do this as we've already done it before
        if (NO_ERROR = lReturn) Then
            wscript.echo lTestNumber & ": - Simple query to root\cimv2 WMI namespace"
            if (goRemoteWin32OS is nothing) Then
                wscript.echo "     FAIL - Simple query failed"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot perform simple query against root\cimv2" & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Simple query succeeded"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if

        ' Test 10: Simple query to root\virtualization namespace. 1.07 - Only if the target is Windows 8 or earlier
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease <= WIN_8) Then
            set colResult = Nothing
            wscript.echo lTestNumber & ": - Simple query to root\virtualization WMI namespace"
            set colResult = goRemoteVirtualization.ExecQuery("select * from msvm_computersystem")
            if (err.number) or (colResult is Nothing) Then
                wscript.echo "     FAIL - Simple query failed"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot perform simple query against root\virtualization" & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Simple query succeeded"
                wscript.echo "          - " & colResult.Count & " computer system(s) located"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if

        ' Test 11: Simple query to root\virtualization\v2 namespace if remote machine is Windows 8
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease >= WIN_8) Then 
            set colResult = Nothing
            wscript.echo lTestNumber & ": - Simple query to root\virtualization\v2 WMI namespace"
            set colResult = goRemoteVirtualizationv2.ExecQuery("select * from msvm_computersystem")
            if (err.number) or (colResult is Nothing) Then
                wscript.echo "     FAIL - Simple query failed"
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Cannot perform simple query against root\virtualization\v2" & vbcrlf
                lReturn = -1  
            else
                wscript.echo "     PASS - Simple query succeeded"
                wscript.echo "          - " & colResult.Count & " computer system(s) located"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if

        ' Test 12: Async notifcation query. First need a sink object
        if (NO_ERROR = lReturn) Then
            set oSink = Wscript.CreateObject("WbemScripting.SWbemSink","SINK_")
            if err.number or (oSink is nothing) THen
                Error "Failed to create SwbemSink object " & err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' 1.07 - Only do to root\virtualization if target is Windows 8 or earlier
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease <= WIN_8) Then
            wscript.echo lTestNumber & ": - Async notification query to root\virtualization WMI namespace"
            lTestNumber = lTestNumber + 1

            'http://msdn.microsoft.com/en-us/library/aa393865(VS.85).aspx
            goRemoteVirtualization.ExecNotificationQueryAsync oSink, _
               "select * from __InstanceCreationEvent within 2 where TargetInstance ISA 'MSVM_ComputerSystem'"
            if (err.number) Then
                lReturn = -1
                OutputAsyncQueryFailureMessage "root\virtualization", err.description
            else
                wscript.echo "     PASS - Async notification query succeeded"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if

        ' 1.03 Test 13: Async notification query but to the virtualization\v2 namespace if remote machine is Windows 8 or later
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease >= WIN_8) Then 
            wscript.echo lTestNumber & ": - Async notification query to root\virtualization\v2 WMI namespace"
            lTestNumber = lTestNumber + 1
            set oSinkv2 = Wscript.CreateObject("WbemScripting.SWbemSink","SINKv2_")
            if err.number or (oSinkv2 is nothing) THen
                Error "Failed to create SwbemSink object " & err.number & " " & err.description
                lReturn = -1
            end if
        end if

        ' 1.07 Bug - Thanks Chris D. Was checking that the local OS is >= WIN_8 when
        ' it should be the remote machine.
        if (NO_ERROR = lReturn) And _
           (glRemoteOSRelease >= WIN_8) Then 
            'http://msdn.microsoft.com/en-us/library/aa393865(VS.85).aspx
            goRemoteVirtualizationv2.ExecNotificationQueryAsync oSink, _
               "select * from __InstanceCreationEvent within 2 where TargetInstance ISA 'MSVM_ComputerSystem'"
            if (err.number) Then
                lReturn = -1
                OutputAsyncQueryFailureMessage "root\virtualization\v2", err.description
            else
                wscript.echo "     PASS - Async notification to root\virtualization\v2 query succeeded"
            end if
            wscript.echo ""
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if


        set colResult = Nothing
        set oSink = Nothing
        set oSinkv2 = Nothing
 
        TestCallsToServer = lReturn

    End Function


    ' ********************************************************************
    ' * OutputAsyncQueryFailureMessage - common as called for 2 namespaces
    ' ********************************************************************

    Sub OutputAsyncQueryFailureMessage(szNamespace, szError)

        wscript.echo "     FAIL - Notification query failed " & szError
        wscript.echo "   "


             
        if (gbComputerIsWorkgroup) and not(gbAnonDCOMAllowed) then
            wscript.echo "This machine is in a workgroup but Anonymous Logon does not have "
            wscript.echo "DCOM access to this machine which is required."
            wscript.echo ""
            wscript.echo "  Run 'hvremote.wsf /mode:client /anondcom:grant' and retry."
        else

            if (glOSRelease <= WIN_8) Then
                wscript.echo "The most common cause of this failure is that you have not restarted the "
                wscript.echo "server after having added a user account for the first time. Either restart "
                wscript.echo "the server, or restart the Windows Management Instrumentation service "
                wscript.echo "and all dependent services on the server before retrying."
                wscript.echo ""
            end if

            wscript.echo "There may be a DNS issue and the server cannot locate this machine."
            wscript.echo "You should check this by performing a ping test from the server to"
            wscript.echo "this machine verifying that the IP address the server is trying to"
            wscript.echo "reach matches the IP address of this machine shown in the output above."
            wscript.echo "Note that it does not matter if the ping succeeds or fails, just that"
            wscript.echo "the IP address is correct."
            wscript.echo " "
            wscript.echo "  Run on " & gszRemoteComputerName & ": ping -4 " & gszLocalComputerName                     
            wscript.echo " "
            wscript.echo "Note that if you do not have DNS in your infrastructure, you can edit"
            wscript.echo "the \windows\system32\drivers\etc\hosts file on the server to add an "
            wscript.echo "entry for " & gszLocalComputerName
            wscript.echo ""
            wscript.echo "If you do have DNS in your infrastructure, you may want to try flushing"
            wscript.echo "the DNS cache on the server, and re-registering against DNS on the client"
            wscript.echo ""
            wscript.echo " Run on " & gszRemoteComputerName & ": ipconfig /flushdns"
            wscript.echo " Run on " & gszLocalComputerName & ": ipconfig /registerdns"
            wscript.echo ""
            wscript.echo "If you are connected over a VPN, see http://tinyurl.com/o4lsbw for"
            wscript.echo "information about another likely cause."
            
            if not(gbComputerIsWorkgroup) then
                wscript.echo ""
                wscript.echo "If the server is in an untrusted domain to this client, you need to"
                wscript.echo "enable anonymous logon access to DCOM on this machine:"
                wscript.echo ""
                wscript.echo "  Run 'hvremote.wsf /mode:client /anondcom:grant' and retry."


                wscript.echo ""
                wscript.echo "If this machine has IPSec policy enforced on it, and the server is in a"
                wscript.echo "workgroup or untrusted domain from this computer, inbound connections"
                wscript.echo "to the client may be blocked by your administrator. You may be able to"
                wscript.echo "temporarily work around this by running net stop bfe on this machine, "
                wscript.echo "but you may lose access to some network services while that service "
                wscript.echo "is stopped. However, this may be against the policy of your administrator."
            end if
                    

            ' Two more common conditions (added in 1.03)
            wscript.echo ""
            wscript.echo "If the server is behind a router/firewall from the client, WMI/DCOM"
            wscript.echo "calls may be being blocked. This will likely be the case if the server"
            wscript.echo "is, for example, on a public IP directly to the Internet. In this"
            wscript.echo "situation, some solutions to consider are: "
            wscript.echo " - VPN to tunnel traffic"
            wscript.echo " - Publish Hyper-V Manager through a TS/RD Gateway"
            wscript.echo " - Access the server through RDP and perform 'local' management"
            wscript.echo " - Run a management machine (physical or virtual) and RDP to that"
            wscript.echo ""

            wscript.echo "There have been several instances of third party firewalls and/or"
            wscript.echo "anti-virus software having adverse effects on remote management."
            wscript.echo "In some cases, disabling that software has not been sufficient to"
            wscript.echo "resolve the issue, and it has been necessary to completely remove"
            wscript.echo "the program."

            wscript.echo ""
            wscript.echo ""
            glWarns = glWarns + 1
            gszWarns = gszWarns & glWarns & ": Cannot perform async WMI query. See detailed resolution steps above." & vbcrlf
      
        end if
    End Sub 'OutputAsyncQueryFailureMessage

    'Sub SINK_OnObjectReady(oObject,oAsyncContext)
    '    wscript.echo "Event occurrend"
    'end sub

    'Sub SINK_OnCompleted(oObject,oAsyncContext)
    '    wscript.echo "Event call complete."
    'End sub

    ' ********************************************************************
    ' * TestCallsToClient: Various tests for server to client connectivity
    ' ********************************************************************
    Function TestCallsToClient(oConnection)

        Dim oShell
        Dim oExec
        Dim lReturn
        Dim lTestNumber
        Dim bRecommendRegularPing

    
        set oShell = Nothing
        set oExec = Nothing
        lReturn = NO_ERROR
        lTestNumber = 1
        bRecommendRegularPing = False

        On error resume next



        wscript.echo " "
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo "Diagnosing connectivity to client:" & gszRemoteComputerName 
        wscript.echo "-------------------------------------------------------------------------------"
        wscript.echo " "

        ' Test 1: Query remote machine for information. This is useful when people only send me output
        ' from one the client, it tells me a little about the server config
        if (NO_ERROR = lReturn) and (not goRemoteCIMv2 is nothing) Then
            wscript.echo lTestNumber & ": - Remote computer network configuration"
            ShowRemoteMachineIPConfiguration()
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 

        end if ' Remote Server Network Configuration

        ' Test 2: Information about remote computer configuration
        if (NO_ERROR = lReturn) and not(goRemoteWin32CS is nothing) and not(goRemoteWin32OS is nothing) Then
            wscript.echo lTestNumber & ": - Remote computer general information"
            ShowRemoteMachineComputerConfiguration()
            glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
        end if

        ' Test 3: WMI style ping & nslookup combined
        if (NO_ERROR = lReturn) Then
            wscript.echo lTestNumber & ": - Ping and resolve name of remote computer"
            lReturn = DoWMIPing (gszRemoteComputerName,oConnection,bRecommendRegularPing)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if ' WMI style ping

        ' Test 4: (Optional) If name resolution failed in test 1, do a regular IPv4 ping just so I can see the output
        ' when people tell me it's not working
        if (NO_ERROR = lReturn) and (bRecommendRegularPing) Then
            lReturn = DoRegularPingTest(lTestNumber,gszRemoteComputerName, 4)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if

        ' Test 5: (Optional) If name resolution failed in test 1, do a regular IPv6 ping just so I can see the output
        ' when people tell me it's not working
        if (NO_ERROR = lReturn) and (bRecommendRegularPing) Then
            lReturn = DoRegularPingTest(lTestNumber,gszRemoteComputerName, 6)
            if (NO_ERROR = lReturn) Then glTestsPassed = glTestsPassed + 1
            lTestNumber = lTestNumber + 1
            if lReturn then
                glWarns = glWarns + 1
                gszWarns = gszWarns & glWarns & ": Some tests were not run due to prior failures" & vbcrlf
            end if 
        end if

        ' Test 6: NSLookup
        if (NO_ERROR = lReturn) Then
            wscript.echo ""
            wscript.echo lTestNumber & ": - NSLookup for remote computers IP address"
            wscript.echo ""
            wscript.echo "     This verifies your DNS infrastructure. For Hyper-V remote management, "
            wscript.echo "     " & gszLocalComputerName & " must be able to resolve the IP address of " & gszRemoteComputerName & "."
            wscript.echo ""
            wscript.echo "     If you do not have a DNS infrastructure, this may legitimately fail."
            wscript.echo "     However, you will have to edit \windows\system32\drivers\etc\hosts on this"
            wscript.echo "     computer to add an entry for " & gszRemoteComputerName & "."
            wscript.echo ""
            wscript.echo "     If you have a DNS infrastructure and this test fails, this is a strong "
            wscript.echo "     indication that Hyper-V remote management will not work."
            wscript.echo ""
            wscript.echo "        a) Verify that " & gszRemoteComputerName & " is the correct client name"
            wscript.echo "        b) On " & gszLocalComputerName & ", run ipconfig /flushdns"
            wscript.echo "        c) On " & gszRemoteComputerName & ", run ipconfig /registerDNS"
            wscript.echo ""
            wscript.echo "     If you have a DNS infrastructure and this test succeeds, verify the IPv4"
            wscript.echo "     address returned matches the IPv4 address of " & gszRemoteComputerName & ". This can be"
            wscript.echo "     found by running ipconfig /all on " & gszRemoteComputerName & "."
            wscript.echo ""
            wscript.echo "     If you find the incorrect IP address is returned, follow steps a) to c) "
            wscript.echo "     described above, plus step d) below."
            wscript.echo ""
            wscript.echo "        d) Check the hosts file on " & gszLocalComputerName & " for incorrect entries."
            wscript.echo ""

            Set oShell = CreateObject("WScript.Shell")
            Set oExec = oShell.Exec("nslookup " & gszRemoteComputerName)
            if (0 <> oExec.ExitCode) Then
                Error "Failed to run nslookup"
                lReturn = -1
            else
                wscript.echo Indent(oExec.StdOut.ReadAll,5)
                wscript.echo Indent(oExec.StdErr.ReadAll,5)
            end if
            lTestNumber = lTestNumber + 1
        end if

        ' Test 7: tracert attempt (IPv4) Added 1.03
        if (NO_ERROR = lReturn) Then

            wscript.echo ""
            wscript.echo lTestNumber & ": - Traceroute using IPv4"
            wscript.echo ""
            wscript.echo "     This attempts to tracert " & gszRemoteComputerName & ". It's aim is to"
            wscript.echo "     determine how many routers are being traversed which may potentially be "
            wscript.echo "     blocking traffic, and may need to be investigated."
            wscript.echo ""
            wscript.echo "     This may take a few seconds..."
            wscript.echo ""
            Set oShell = CreateObject("WScript.Shell")
            Set oExec = oShell.Exec("tracert -4 " & gszRemoteComputerName)
            if (0 <> oExec.ExitCode) Then
                Error "Failed to run tracert"
                lReturn = -1
            else
                wscript.echo Indent(oExec.StdOut.ReadAll,5)
                wscript.echo Indent(oExec.StdErr.ReadAll,5)
            end if
            lTestNumber = lTestNumber + 1
        end if
    


        ' Test 8: tracert attempt (IPv6) Added 1.03

        if (NO_ERROR = lReturn) Then
            wscript.echo ""
            wscript.echo lTestNumber & ": - Traceroute using IPv6"
            wscript.echo ""
            Set oShell = CreateObject("WScript.Shell")
            Set oExec = oShell.Exec("tracert -6 " & gszRemoteComputerName)
            if (0 <> oExec.ExitCode) Then
                Error "Failed to run tracert"
                lReturn = -1
            else
                wscript.echo Indent(oExec.StdOut.ReadAll,5)
                wscript.echo Indent(oExec.StdErr.ReadAll,5)
            end if
            lTestNumber = lTestNumber + 1
        End if


        set oShell = Nothing
        set oExec = Nothing

        TestCallsToClient = lReturn

    End Function

    Function Indent(s,n)
        On error resume next
        Indent = ""
        if len(s) Then Indent = Space(n) & "> " & Replace(s,vbcrlf,vbcrlf & Space(n) & "> ")
    End Function


    ' ********************************************************************
    ' * GetRemoteMachineInfo: Silently determine info of remote target
    ' * This sets the following global variables if successful:
    ' *   - goRemoteCIMv2 		Connection to cimv2 namespace
    ' *   - goRemoteWin32CS             Object win32_computersystem
    ' *   - goRemoteWin32OS             Object win32_operatingsystem
    ' *   - glRemoteInstalledOS         HVREMOTE_INSTALLED_OS_CLIENT/SERVER
    ' *   - glRemoteOSRelease           WIN_6/7/8/....
    ' *   - goRemoteVirtualization      Connection to virtualization namespace
    ' *   - goRemoteVirtualizationV2    If WIN_8+, Connection to virtualizationV2 namespace
    ' ********************************************************************
    Function GetRemoteMachineInfo()

        Dim lReturn			' Function return
        Dim colResult                   ' Collection of objects from WMI query
        Dim oResult                     ' For iterating through collection
        Dim arrBuildOfTarget            ' This holds the build of the target in array elements ie (6)(1)(7600) for R2 RTM
    
        set colResult = Nothing
        set oResult = Nothing
        lReturn = NO_ERROR

        On error resume next

        ' Connect to cimv2 namespace
        if (NO_ERROR = lReturn) Then
            lReturn = ConnectNameSpace("root\cimv2", gszRemoteComputerName, goRemoteCIMv2, True)
            if (lReturn) or (goRemoteCIMv2 is Nothing) Then
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: Failed to connect namespace root\CIMV2"
                lReturn = -1  
            end if
        end if

        ' Query win32_computersystem
        if (NO_ERROR = lReturn) and not (goRemoteCIMv2 is nothing) Then
            set colResult = Nothing
            set colResult = goRemoteCIMV2.ExecQuery("select * from win32_computersystem")
            if (err.number) or (colResult is Nothing) Then
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: Failed to query win32_computersystem"
                lReturn = -1  
            end if
        end if

        if (NO_ERROR = lReturn) and not(colResult is nothing) Then
            for each oResult in colResult
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: oResult" & vbcrlf & oResult.GetObjectText_
                set goRemoteWin32CS = oResult
            next
            set colResult = Nothing
        end if

        if (NO_ERROR = lReturn) and not (goRemoteCIMV2 is nothing) Then
            set colResult = goRemoteCIMV2.ExecQuery("select * from win32_operatingsystem")
            if (err.number) or (colResult is Nothing) Then
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: Failed to query win32_operatingsystem"
                lReturn = -1  
            end if
        end if

        if (NO_ERROR = lReturn) and not(colResult is nothing) Then
            for each oResult in colResult
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: oResult" & vbcrlf & oResult.GetObjectText_
                set goRemoteWin32OS = oResult
            next
            set colResult = Nothing
        end if

         ' Is the remote machine client or server?
         if (NO_ERROR = lReturn) and (not(goRemoteWin32OS is Nothing)) then
            if goRemoteWin32OS.ProductType = 1 Then
                glRemoteInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT
            else
                glRemoteInstalledOS = HVREMOTE_INSTALLED_OS_SERVER
            end if
         end if

         if (NO_ERROR = lReturn) and (not(goRemoteWin32OS is Nothing)) then
             arrBuildOfTarget = split(lcase(goRemoteWin32OS.Version),".")
             if ubound(arrBuildOfTarget) < 2 Then
                 ' This really should never happen! We know goRemoteWin32OS is not null
                 ' and for Windows not to populate it would be very unusual. But let's be safe.
                 Error "Failed to parse build of target: " & goRemoteWin32OS.Version
                 lReturn = -1
             else
                 glRemoteOSRelease = WIN_UNKNOWN

                 if arrBuildOfTarget(0) < 6 Then
                     glWarns = glWarns + 1
                     Error "Remote machine is pre Windows Vista. Really???!!"
                     wscript.quit              
                 end if
               
                 if arrBuildOfTarget(0) = 6 and arrBuildOfTarget(1) = 0 Then 
                     if glRemoteInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT Then
                         glWarns = glWarns + 1
                         gszWarns = gszWarns & glWarns & ": Remote machine is Windows Vista. Really???!!" & vbcrlf
                     end if
                     glRemoteOSRelease = WIN_6
                 end if

                 if arrBuildOfTarget(0) = 6 and arrBuildOfTarget(1) = 1 Then
                     if glRemoteInstalledOS = HVREMOTE_INSTALLED_OS_CLIENT Then
                         glWarns = glWarns + 1
                         gszWarns = gszWarns & glWarns & ": Remote machine is Windows 7!" & vbcrlf
                     end if
                     glRemoteOSRelease = WIN_7
                 end if

                 if arrBuildOfTarget(0) = 6 and arrBuildOfTarget(1) = 2 Then 
                     glRemoteOSRelease = WIN_8
                 end if


                 if arrBuildOfTarget(0) = 6 and arrBuildOfTarget(1) = 3 Then 
                     glRemoteOSRelease = WIN_8POINT1
                 end if

                 if (arrBuildOfTarget(0) = 6 and arrBuildOfTarget(1) > 3) or _
                    (arrBuildOfTarget(0) > 6) Then 
                     glRemoteOSRelease = WIN_LATER
                 end if
             end if
        end if


        ' Connect to virtualization namespace if we are in client mode connecting to a server
        ' 1.07 Only do this if target is Windows 8 or earlier
        if (NO_ERROR = lReturn) and (glClientServerMode = HVREMOTE_MODE_CLIENT) and (glRemoteOSRelease <= WIN_8) Then
            lReturn = ConnectNameSpace("root\virtualization", gszRemoteComputerName, goRemoteVirtualization, True)
            if (lReturn) or (goRemoteVirtualization is Nothing) Then
                set goRemoteVirtualization = Nothing
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: Failed to connect namespace root\virtualization"
                lReturn = -1  
            end if
        end if

        ' Connect to virtualization\v2 namespace if we are in client mode connecting to a WIN_8 server
        if (NO_ERROR = lReturn) and (glClientServerMode = HVREMOTE_MODE_CLIENT) and (glRemoteOSRelease >= WIN_8) Then
            lReturn = ConnectNameSpace("root\virtualization\v2", gszRemoteComputerName, goRemoteVirtualizationV2, True)
            if (lReturn) or (goRemoteVirtualizationV2 is Nothing) Then
                set goRemoteVirtualizationv2 = Nothing
                Dbg DBG_EXTRA, "GetRemoteMachineInfo: Failed to connect namespace root\virtualization\v2"
                lReturn = -1  
            end if
        end if

	
        set colResult = Nothing
        set oResult = Nothing

        GetRemoteMachineInfo = lReturn

    End Function


    ' ********************************************************************
    ' * GetEnvironmentVariable: Does exactly what it says on the tin
    ' ********************************************************************
    Function GetEnvironmentVariable(szWhat, byref szValue)

        On error resume next


        Dim WshShell          ' For accessing the environment
        Dim oProcess          ' For the process environment variables
        Dim lReturn           ' Function return value

        On error resume next

        set WshShell = Nothing
        set oProcess = Nothing
        lReturn = NO_ERROR
        szValue = ""


        if (NO_ERROR = lReturn) Then
            Set WshShell = CreateObject("WScript.Shell")
            if (err.number) or (WshShell is nothing) Then
                Error "Failed to instantiate WScript.Shell"
                Error err.description & " " & err.number
                lReturn = -1
                wscript.quit
            end if
        end if

        if (NO_ERROR = lReturn) Then
            set oProcess = WshShell.Environment("PROCESS")
            if (err.number) or (oProcess is nothing) Then
                Error "Failed to obtain environment for current process"
                Error err.description & " " & err.number
                lReturn = -1
                wscript.quit
            end if
        end if


        ' Get the computername
        if (NO_ERROR = lReturn) Then
            szValue = oProcess.Item(szWhat)
            if (err.number) or (0 = len(szValue)) Then
                Error "Failed to obtain " & szWhat & " from environment"
                Error err.description & " " & err.number
                lReturn = -1
                wscript.quit
            end if
        end if

        GetEnvironmentVariable = lReturn
        set WshShell = Nothing
        set oProcess = Nothing


    End Function

    ' ********************************************************************
    ' * ConfigureClientTracingOn: Turns on tracing for the client UI
    ' ********************************************************************
    Function ConfigureClientTracingOn()

        On error resume next

        Dim lReturn           ' Function return value
        Dim szAppData         ' Environment Variable
        Dim szContents        ' Contents of the file we are writing
        Dim szFile            ' The full path to file
 
        lReturn = NO_ERROR
        szAppData = ""
        szFile = ""

        ' Need the appdata environment variable
        if (NO_ERROR = lReturn) Then
            lReturn = GetEnvironmentVariable("APPDATA", szAppData)
            if (lReturn) Then
                Error "Failed to get APPDATA"
                lReturn = -1
                wscript.quit
            end if
        end if


        ' Delete file if already exists
        if (NO_ERROR = lReturn) Then
             szFile = szAppData & "\Microsoft\Windows\Hyper-V\Client\1.0\VMClientTrace.config"
             if FileExists(szFile) Then
                 lReturn = DeleteFile(szFile)
                 if lReturn then
                     Error "Failed to delete old VMClientTrace.config file"
                     lReturn = -1
                 else
                     wscript.echo "INFO: Removed old trace file"
                 end if
              end if
        end if

        ' Write contents
        if (NO_ERROR = lReturn) Then
            if (glOSRelease < WIN_8) Then
                szContents = "<?xml version='1.0' encoding='utf-8'?>" & vbcrlf & _
                             "<configuration>" & vbcrlf & _
                             "  <Microsoft.Virtualization.Client.TraceConfigurationOptions>" & vbcrlf & _
                             "    <setting name='TraceTagFormat' type='System.Int32'>"  & vbcrlf & _
                             "      <value>3</value>"  & vbcrlf & _
                             "    </setting>"  & vbcrlf & _
                             "    <setting name='BrowserTraceLevel' type='System.Int32'>"  & vbcrlf & _
                             "      <value>6</value>"  & vbcrlf & _
                             "    </setting>"  & vbcrlf & _
                             "    <setting name='VMConnectTraceLevel' type='System.Int32'>"  & vbcrlf & _
                             "      <value>6</value>"  & vbcrlf & _
                             "    </setting>"  & vbcrlf & _
                             "    <setting name='VHDInspectTraceLevel' type='System.Int32'>"  & vbcrlf & _
                             "      <value>6</value>"  & vbcrlf & _
                             "    </setting>"  & vbcrlf & _
                             "  </Microsoft.Virtualization.Client.TraceConfigurationOptions>"  & vbcrlf & _
                             "</configuration>"  & vbcrlf
            else
                szContents = "<?xml version='1.0' encoding='utf-8'?>" & vbcrlf & _
                             "<configuration>" & vbcrlf & _
                             "    <Microsoft.Virtualization.Client.TraceConfigurationOptions>" & vbcrlf & _
                             "        <setting name='TraceTagFormat' type='System.Int32'>" & vbcrlf & _
                             "            <value>3</value>" & vbcrlf & _
                             "        </setting>" & vbcrlf & _
                             "        <setting name='BrowserTraceLevel' type='System.Int32'>" & vbcrlf & _
                             "            <value>71</value>" & vbcrlf & _
                             "        </setting>" & vbcrlf & _
                             "        <setting name='VMConnectTraceLevel' type='System.Int32'>" & vbcrlf & _
                             "            <value>71</value>" & vbcrlf & _
                             "        </setting>" & vbcrlf & _
                             "        <setting name='InspectVhdTraceLevel' type='System.Int32'>" & vbcrlf & _
                             "            <value>71</value>" & vbcrlf & _
                             "        </setting>" & vbcrlf & _
                             "    </Microsoft.Virtualization.Client.TraceConfigurationOptions>" & vbcrlf & _
                             "</configuration>" & vbcrlf
            end if
            szContents = Replace(szContents,"'",chr(34))
            lReturn = WriteFile(szFile,szContents)
        end if


        if (NO_ERROR = lReturn) Then
            wscript.echo "INFO: UI tracing has been turned on."
            wscript.echo "INFO: Log files are written to '%temp%\VMBrowser_Trace_YYYYMMDDHHMMSS.log'."
            wscript.echo "WARN: You must restart Hyper-V manager for the change to take effect."
            glWarns = glWarns + 1
            gszWarns = gszWarns & glWarns & ": Hyper-V manager must be restarted for the change to take effect" & vbcrlf
        end if

        ConfigureClientTracingOn = lReturn

    end Function

    ' ********************************************************************
    ' * FileExists: Returns true/false
    ' ********************************************************************
    Function FileExists(szFile)

        On error resume next
        Dim lReturn
        Dim oFSO
        
        lReturn = NO_ERROR
        set oFSO = Nothing
        FileExists = False

        if (NO_ERROR = lReturn) Then
            set oFSO = CreateObject("Scripting.FileSystemObject")
            if (err.number) or (oFSO is nothing) Then
                Error "Failed to create object scripting.filesystemobject: " & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            FileExists = oFSO.FileExists(szFile)
        end if

        set oFSO = Nothing

    End Function

    ' ********************************************************************
    ' * DeleteFile: Removes a file from disk. Used for client tracing.
    ' ********************************************************************
    Function DeleteFile(szFile)
        On error resume next
        Dim lReturn
        Dim oFSO
        
        lReturn = NO_ERROR
        set oFSO = Nothing

        if (NO_ERROR = lReturn) Then
            set oFSO = CreateObject("Scripting.FileSystemObject")
            if (err.number) or (oFSO is nothing) Then
                Error "Failed to create object scripting.filesystemobject: " & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            oFSO.DeleteFile(szFile)
            if (err.number) Then
                Error "Failed to delete " & szFile & vbcrlf & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        set oFSO = Nothing
        DeleteFile = lReturn

    End Function

    ' ********************************************************************
    ' * WriteFile: Writes a blob of text to a file
    ' ********************************************************************
    Function WriteFile(szFile, szContents)
        On error resume next
        Dim lReturn
        Dim oFSO
        Dim oTextStream
        
        lReturn = NO_ERROR
        set oFSO = Nothing
        set oTextStream = Nothing

        if (NO_ERROR = lReturn) Then
            set oFSO = CreateObject("Scripting.FileSystemObject")
            if (err.number) or (oFSO is nothing) Then
                Error "Failed to create object scripting.filesystemobject: " & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            set oTextStream = oFSO.OpenTextFile(szFile,2,True)
            if (err.number) or (oTextStream is nothing) Then
                Error "Failed to OpenTextFile " & szFile & vbcrlf & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            oTextStream.Write(szContents)
            if (err.number) Then
                Error "Failed to write " & szFile & vbcrlf & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        if (NO_ERROR = lReturn) Then
            oTextStream.Close
            if (err.number) Then
                Error "Failed to close " & szFile & vbcrlf & err.description & " " & hex(err.number)
                lReturn = -1
            end if
        end if

        set oFSO = Nothing
        set oTextStream = Nothing
        WriteFile = lReturn

    End Function


    ' ********************************************************************
    ' * ConfigureClientTracingOff: Turns off tracing for the client UI
    ' ********************************************************************
    Function ConfigureClientTracingOff()

        On error resume next

        Dim lReturn           ' Function return value
        Dim szAppData         ' Environment Variable
        Dim szContents        ' Contents of the file we are writing
        Dim szFile            ' The full path to file
 
        lReturn = NO_ERROR
        szAppData = ""
        szFile = ""

        ' Need the appdata environment variable
        if (NO_ERROR = lReturn) Then
            lReturn = GetEnvironmentVariable("APPDATA", szAppData)
            if (lReturn) Then
                Error "Failed to get APPDATA"
                lReturn = -1
                wscript.quit
            end if
        end if


        ' Delete file if already exists
        if (NO_ERROR = lReturn) Then
             szFile = szAppData & "\Microsoft\Windows\Hyper-V\Client\1.0\VMClientTrace.config"
             if FileExists(szFile) Then
                 lReturn = DeleteFile(szFile)
                 if lReturn then
                     Error "Failed to delete old VMClientTrace.config file"
                     lReturn = -1
                 else
                     wscript.echo "INFO: UI tracing has been turned off."
                     wscript.echo "WARN: You must restart Hyper-V manager for the change to take effect."
                     glWarns = glWarns + 1
                     gszWarns = gszWarns & glWarns & ": Hyper-V manager must be restarted for the change to take effect" & vbcrlf

                  end if
              else
                     wscript.echo "WARN: UI tracing is already turned off."
                     glWarns = glWarns + 1
                     gszWarns = gszWarns & glWarns & ": No changes made to tracing setting" & vbcrlf
              end if
        end if

        ConfigureClientTracingOff = lReturn


    end Function

    ' ********************************************************************
    ' * CheckTracing: Looks to see if tracing is turned on (file exists, not the content)
    ' ********************************************************************
    Sub CheckTracing()

        On error resume next

        Dim lReturn           ' Function return value
        Dim szAppData         ' Environment Variable
        Dim szContents        ' Contents of the file we are writing
        Dim szFile            ' The full path to file
 
        lReturn = NO_ERROR
        szAppData = ""
        szFile = ""

        ' Need the appdata environment variable
        if (NO_ERROR = lReturn) Then
            lReturn = GetEnvironmentVariable("APPDATA", szAppData)
            if (lReturn) Then
                Error "Failed to get APPDATA"
                lReturn = -1
                wscript.quit
            end if
        end if

        ' Check for existance
        if (NO_ERROR = lReturn) Then
             szFile = szAppData & "\Microsoft\Windows\Hyper-V\Client\1.0\VMClientTrace.config"
             if FileExists(szFile) then
                 wscript.echo "WARN: UI tracing is turned on. Use 'hvremote /trace:off' to turn off"
                 glWarns = glWarns + 1
                 gszWarns = gszWarns & glWarns & ": UI tracing is turned on. Run 'hvremote /trace:off'" & vbcrlf
              end if
        end if

    end Sub


    ' ********************************************************************
    ' * IsQFEInstalled: Checks for a particular QFE
    ' ********************************************************************
    Function IsQFEInstalled(oConnection, szQFE)

        Dim colQFEs                    ' Collection of installed hotfixes
        Dim oQFE                       ' For enumerating the hotfixes

        On error resume next

        set colQFEs = Nothing
        set oQFE = Nothing

        set colQFEs = oConnection.ExecQuery("select * from win32_quickfixengineering")
        for each oQFE in colQFEs
           if lcase(oQFE.HotFixID) = lcase(szQFE) or lcase(oQFE.HotFixID) = "kb" & szQFE Then
               IsQFEInstalled = True
               exit for
           end if
        next

        set colQFEs = Nothing
        set oQFE = Nothing

    End Function

    ' ********************************************************************
    ' * IsMachineConfiguredForDA: Looks to see if Direct Access is configured
    ' ********************************************************************
    Function IsMachineConfiguredForDA(oConnection)

        Dim lReturn
        Dim bConfigured
        Dim szShellOutput    
        Dim lStart
        Dim lEnd
        Dim lMid


        lReturn = NO_ERROR
        bConfigured = False
        szShellOutput = ""
        lStart = 0
        lMid = 0
        lEnd = 0

        ' Windows 6, not available
        if (glOSRelease = WIN_6) Then
            bConfigured = False
        end if

        ' Windows 7. Less ugly way... 
        if (glOSRelease = WIN_7) Then
            ' Not guaranteed, but may work. http://technet.microsoft.com/en-us/library/ff384241.aspx
            bConfigured = TestService(oConnection,"DcaSvc", SERVICE_TEST_RUNNING)
        end if

        ' Windows 7. Alternate, more ugly way... parse the output of netsh dns show state
        if (glOSRelease = WIN_7) and (not bConfigured) Then

            if (NO_ERROR = lReturn) Then
                lReturn = RunShellCmd ("netsh dns show state","",False,szShellOutput,True)
            end if

            ' en-us. Not perfect for other languages...
            ' Direct Access Settings                : Not Configured
            ' Direct Access Settings                : Configured and Disabled
            if (NO_ERROR = lReturn) Then
                lStart = instr(1,szShellOutput, "Direct Access Settings")
                if (lStart>0) Then 
                    lMid = instr(lStart,szShellOutput,":")
                    if (lMid > lStart) then
                        lEnd = instr(lMid,szShellOutput,chr(13))
                        if (lEnd < len(szShellOutput)) Then
                           if lcase(mid(szShellOutput,lMid+2,lEnd-lMid-2)) <> "not configured" then
                               bConfigured = True
                           end if
                        end if
                    end if
                end if
            end if
        end if ' WIN_7 Version

        ' TODO - Have a really complex way for Windows 7 as well, but saving that for another release. See 
        ' notes in the release folder support docs for how to if I have a spare weekend. 

        ' Windows 8, looks to see if the ncasvc is running. So easy in comparison!
        if (glOSRelease >= WIN_8) Then
            bConfigured = TestService(oConnection,"NcaSvc", SERVICE_TEST_RUNNING)
        end if    
   
        IsMachineConfiguredForDA = bConfigured

    End Function 'IsMachineConfiguredForDA

   ]]>

  </script>
 </job>
</package>

