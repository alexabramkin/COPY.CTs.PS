#
# Copyright (c) Microsoft Corporation.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#Helper functions for PackageManagement DSC Resouces

Import-LocalizedData -BindingVariable LocalizedData -filename PackageManagementDscUtilities.strings.psd1


 Function ExtractArguments
{
    <#
    .SYNOPSIS

    This is a helper function that extract the parameters from a given table. 

    .PARAMETER FunctionBoundParameters
    Specifies the hashtable containing a set of parameters to be extracted

    .PARAMETER ArgumentNames
    Specifies A list of arguments you want to extract
    #>

    Param
    (
        [parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $FunctionBoundParameters,

        #A list of arguments you want to extract
        [parameter(Mandatory = $true)]
        [System.String[]]$ArgumentNames
    )

    Write-Verbose -Message ($LocalizedData.CallingFunction -f $($MyInvocation.mycommand))

    $returnValue=@{}

    foreach ($arg in $ArgumentNames)
    {
        if($FunctionBoundParameters.ContainsKey($arg))
        {
            #Found an argument we are looking for, so we add it to return collection
            $returnValue.Add($arg,$FunctionBoundParameters[$arg])
        }
    }

    return $returnValue
 }

function ThrowError
{
    <#
    .SYNOPSIS

    This is a helper function that throws an error. 

    .PARAMETER ExceptionName
    Specifies the type of errors, e.g. System.ArgumentException

    .PARAMETER ExceptionMessage
    Specifies the exception message

    .PARAMETER ErrorId
    Specifies an identifier of the error

    .PARAMETER ErrorCategory
    Specifies the error category, e.g., InvalidArgument defined in System.Management.Automation. 

    #>

    param
    (        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ExceptionMessage,      
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory
    )
    
    Write-Verbose -Message ($LocalizedData.CallingFunction -f $($MyInvocation.mycommand))
        
    $exception   = New-Object -TypeName $ExceptionName -ArgumentList $ExceptionMessage;
    $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList ($exception, $ErrorId, $ErrorCategory, $null)    
    throw $errorRecord
}

Function ValidateArgument
{
    <#
    .SYNOPSIS

    This is a helper function that validates the arguments. 

    .PARAMETER Argument
    Specifies the argument to be validated.

    .PARAMETER Type
    Specifies the type of argument.
    #>

    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Argument,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$Type,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$ProviderName
    )

    Write-Verbose -Message ($LocalizedData.CallingFunction -f $($MyInvocation.mycommand))

    switch ($Type)
    {

        "SourceUri"
        {
            # Checks whether given URI represents specific scheme
            # Most common schemes: file, http, https, ftp        
            $scheme =@('http', 'https', 'file', 'ftp')
 
            $newUri = $Argument -as [System.URI]  
            $returnValue = ($newUri -and $newUri.AbsoluteURI -and ($scheme -icontains $newuri.Scheme)) 

            if ($returnValue -eq $false)
            {                
                ThrowError  -ExceptionName "System.ArgumentException" `
                            -ExceptionMessage ($LocalizedData.InValidUri -f $Argument)`
                            -ErrorId "InValidUri" `
                            -ErrorCategory InvalidArgument
            }
            
            #Check whether it's a valid uri. Wait for the response within 2mins.
            <#$result = Invoke-WebRequest $newUri -TimeoutSec 120 -UseBasicParsing -ErrorAction SilentlyContinue

            if ($null -eq (([xml]$result.Content).service ))
            {
                ThrowError  -ExceptionName "System.ArgumentException" `
                            -ExceptionMessage ($LocalizedData.InValidUri -f $Argument)`
                            -ErrorId "InValidUri" `
                            -ErrorCategory InvalidArgument
            }#>
                                         
        }
        "DestinationPath"
        {
            $returnValue = Test-Path -Path $Argument
            if ($returnValue -eq $false)
            {
                ThrowError  -ExceptionName "System.ArgumentException" `
                            -ExceptionMessage ($LocalizedData.PathDoesNotExist -f $Argument)`
                            -ErrorId "PathDoesNotExist" `
                            -ErrorCategory InvalidArgument
            }
        }
        "PackageSource"
        {      
            #Argument can be either the package source Name or source Uri.  
            
            #Check if the source is a uri 
            $uri = $Argument -as [System.URI]  

            if($uri -and $uri.AbsoluteURI) 
            {
                # Check if it's a valid Uri
                ValidateArgument -Argument $Argument -Type "SourceUri" -ProviderName $ProviderName
            }
            else
            {
                #Check if it's a registered package source name                                                             
                $source = PackageManagement\Get-PackageSource -Name $Argument -ProviderName $ProviderName -verbose -ErrorVariable ev
                if ((-not $source) -or $ev) 
                {
                    #We do not need to throw error here as Get-PackageSource does already
                    Write-Verbose -Message ($LocalizedData.SourceNotFound -f $source)                
                }
            }
        }
        default
        {
            ThrowError  -ExceptionName "System.ArgumentException" `
                        -ExceptionMessage ($LocalizedData.UnexpectedArgument -f $Type)`
                        -ErrorId "UnexpectedArgument" `
                        -ErrorCategory InvalidArgument
        }
     }           
}

Function ValidateVersionArgument
{
    <#
    .SYNOPSIS

    This is a helper function that does the version validation. 

    .PARAMETER RequiredVersion
    Provides the required version.

    .PARAMETER MaximumVersion
    Provides the maximum version.

    .PARAMETER MinimumVersion
    Provides the minimum version.
    #>

    [CmdletBinding()]
    param
    (
        [string]$RequiredVersion,
        [string]$MinimumVersion,
        [string]$MaximumVersion

    )
         
    Write-Verbose -Message ($LocalizedData.CallingFunction -f $($MyInvocation.mycommand))

    $isValid = $false
         
    #Case 1: No further check required if a user provides either none or one of these: minimumVersion, maximumVersion, and requiredVersion
    if ($PSBoundParameters.Count -le 1)
    {
        return $true
    }

    #Case 2: #If no RequiredVersion is provided 
    if (-not $PSBoundParameters.ContainsKey('RequiredVersion'))
    {
        #If no RequiredVersion, both MinimumVersion and MaximumVersion are provided. Otherwise fall into the Case #1
        $isValid = $PSBoundParameters['MinimumVersion'] -le $PSBoundParameters['MaximumVersion']
    }
    
    #Case 3: RequiredVersion is provided. 
    #        In this case  MinimumVersion and/or MaximumVersion also are provided. Otherwise fall in to Case #1.
    #        This is an invalid case. When RequiredVersion is provided, others are not allowed. so $isValid is false, which is already set in the init

    if ($isValid -eq $false)
    {        
        ThrowError  -ExceptionName "System.ArgumentException" `
                    -ExceptionMessage ($LocalizedData.VersionError)`
                    -ErrorId "VersionError" `
                    -ErrorCategory InvalidArgument
    }
}

Function Get-InstallationPolicy
{
    <#
    .SYNOPSIS

    This is a helper function that retrives the InstallationPolicy from the given repository. 

    .PARAMETER RepositoryName
    Provides the repository Name.

    #>

    Param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]$RepositoryName
    )

    Write-Verbose -Message ($LocalizedData.CallingFunction -f $($MyInvocation.mycommand))

    $repositoryobj = PackageManagement\Get-PackageSource -Name $RepositoryName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

    if ($repositoryobj)
    {      
        return $repositoryobj.IsTrusted
    }                  
}

# SIG # Begin signature block
# MIIasAYJKoZIhvcNAQcCoIIaoTCCGp0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUJF+Chk1Zl189V26e1OOHUNYB
# SwegghWDMIIEwzCCA6ugAwIBAgITMwAAALgYPKjXA3t9ggAAAAAAuDANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwOTA3MTc1ODQ1
# WhcNMTgwOTA3MTc1ODQ1WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjdEMkUtMzc4Mi1CMEY3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnaLG0E/Tu86w
# owRN6AiltXrcmafSmbdl78ODWZEpnPV2rV91m1UxxEVn7L1gt/exIySWKBgy0zIH
# XIXBnVmOO7s8588G/Qq0f7pLzFnfFXFBzDBlVgVHmB7Ak/SQ66Is5TEqd0TyF9ff
# Gv2ooVfaWe2S4RXSp7lhQfB7oH4e2jevuq95SAdNGFkzOhJqmxuaFpU9rXDJqKPx
# QTqvv8qfnaKZBfQre8sfpaFbJOpaZgx0zWcCL4OKtxiRaC1SwPn7PUoT6aXD1lbQ
# 2A1aXm1RelZDXObiflpUSLnSZEKs37JvErwzoIIz1jA2DT8UfEUBfO+0NLRogoL/
# 87WD7Bv5fQIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFJG/eoXgR5qRzeoSYD0njQuK
# MU6CMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBACNjoS6XJKHJZbomlN/SYgCUqHRYj2pE3Gad4Ey0L5lo2o0w
# pbIXKvWLcuRw4HjGQOeu59IPh2YoJszmbiMYeGI7fAan95UyvaLC1TJ8bdljy5nF
# tQCuxVP0RfhNrp9DYNs2baYB7FIe9DQ3fjb3OuoEYIcjFAl8JEX/l5ANWcS1n9SN
# KagAdS/9piabhNUutyV4xb5HuQXBiXZZmHzYLdenq+SkHYlL1/Yu2Hx6Dx2d/CCh
# oLLfMJ+9bTinZLxL6kL75Nv08HyBlilnpgDMO30o8M/udMfcIj8BszosMJ84cTw+
# QR7BgiBbz2Lkk3UufsxgSSggcyhpJH8MlwgoLoEwggTtMIID1aADAgECAhMzAAAB
# QJap7nBW/swHAAEAAAFAMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE2MDgxODIwMTcxN1oXDTE3MTEwMjIwMTcxN1owgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBANtLi+kDal/IG10KBTnk1Q6S0MThi+ikDQUZWMA81ynd
# ibdobkuffryavVSGOanxODUW5h2s+65r3Akw77ge32z4SppVl0jII4mzWSc0vZUx
# R5wPzkA1Mjf+6fNPpBqks3m8gJs/JJjE0W/Vf+dDjeTc8tLmrmbtBDohlKZX3APb
# LMYb/ys5qF2/Vf7dSd9UBZSrM9+kfTGmTb1WzxYxaD+Eaxxt8+7VMIruZRuetwgc
# KX6TvfJ9QnY4ItR7fPS4uXGew5T0goY1gqZ0vQIz+lSGhaMlvqqJXuI5XyZBmBre
# ueZGhXi7UTICR+zk+R+9BFF15hKbduuFlxQiCqET92ECAwEAAaOCAWEwggFdMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSc5ehtgleuNyTe6l6pxF+QHc7Z
# ezBSBgNVHREESzBJpEcwRTENMAsGA1UECxMETU9QUjE0MDIGA1UEBRMrMjI5ODAz
# K2Y3ODViMWMwLTVkOWYtNDMxNi04ZDZhLTc0YWU2NDJkZGUxYzAfBgNVHSMEGDAW
# gBTLEejK0rQWWAHJNy4zFha5TJoKHzBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNDb2RTaWdQQ0Ff
# MDgtMzEtMjAxMC5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY0NvZFNpZ1BDQV8wOC0z
# MS0yMDEwLmNydDANBgkqhkiG9w0BAQUFAAOCAQEAa+RW49cTHSBA+W3p3k7bXR7G
# bCaj9+UJgAz/V+G01Nn5XEjhBn/CpFS4lnr1jcmDEwxxv/j8uy7MFXPzAGtOJar0
# xApylFKfd00pkygIMRbZ3250q8ToThWxmQVEThpJSSysee6/hU+EbkfvvtjSi0lp
# DimD9aW9oxshraKlPpAgnPWfEj16WXVk79qjhYQyEgICamR3AaY5mLPuoihJbKwk
# Mig+qItmLPsC2IMvI5KR91dl/6TV6VEIlPbW/cDVwCBF/UNJT3nuZBl/YE7ixMpT
# Th/7WpENW80kg3xz6MlCdxJfMSbJsM5TimFU98KNcpnxxbYdfqqQhAQ6l3mtYDCC
# BbwwggOkoAMCAQICCmEzJhoAAAAAADEwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmS
# JomT8ixkARkWA2NvbTEZMBcGCgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UE
# AxMkTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTEwMDgz
# MTIyMTkzMloXDTIwMDgzMTIyMjkzMloweTELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCycllcGTBkvx2aYCAg
# Qpl2U2w+G9ZvzMvx6mv+lxYQ4N86dIMaty+gMuz/3sJCTiPVcgDbNVcKicquIEn0
# 8GisTUuNpb15S3GbRwfa/SXfnXWIz6pzRH/XgdvzvfI2pMlcRdyvrT3gKGiXGqel
# cnNW8ReU5P01lHKg1nZfHndFg4U4FtBzWwW6Z1KNpbJpL9oZC/6SdCnidi9U3RQw
# WfjSjWL9y8lfRjFQuScT5EAwz3IpECgixzdOPaAyPZDNoTgGhVxOVoIoKgUyt0vX
# T2Pn0i1i8UU956wIAPZGoZ7RW4wmU+h6qkryRs83PDietHdcpReejcsRj1Y8wawJ
# XwPTAgMBAAGjggFeMIIBWjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTLEejK
# 0rQWWAHJNy4zFha5TJoKHzALBgNVHQ8EBAMCAYYwEgYJKwYBBAGCNxUBBAUCAwEA
# ATAjBgkrBgEEAYI3FQIEFgQU/dExTtMmipXhmGA7qDFvpjy82C0wGQYJKwYBBAGC
# NxQCBAweCgBTAHUAYgBDAEEwHwYDVR0jBBgwFoAUDqyCYEBWJ5flJRP8KuEKU5VZ
# 5KQwUAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEB
# BEgwRjBEBggrBgEFBQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNyb3NvZnRSb290Q2VydC5jcnQwDQYJKoZIhvcNAQEFBQADggIBAFk5
# Pn8mRq/rb0CxMrVq6w4vbqhJ9+tfde1MOy3XQ60L/svpLTGjI8x8UJiAIV2sPS9M
# uqKoVpzjcLu4tPh5tUly9z7qQX/K4QwXaculnCAt+gtQxFbNLeNK0rxw56gNogOl
# VuC4iktX8pVCnPHz7+7jhh80PLhWmvBTI4UqpIIck+KUBx3y4k74jKHK6BOlkU7I
# G9KPcpUqcW2bGvgc8FPWZ8wi/1wdzaKMvSeyeWNWRKJRzfnpo1hW3ZsCRUQvX/Ta
# rtSCMm78pJUT5Otp56miLL7IKxAOZY6Z2/Wi+hImCWU4lPF6H0q70eFW6NB4lhhc
# yTUWX92THUmOLb6tNEQc7hAVGgBd3TVbIc6YxwnuhQ6MT20OE049fClInHLR82zK
# wexwo1eSV32UjaAbSANa98+jZwp0pTbtLS8XyOZyNxL0b7E8Z4L5UrKNMxZlHg6K
# 3RDeZPRvzkbU0xfpecQEtNP7LN8fip6sCvsTJ0Ct5PnhqX9GuwdgR2VgQE6wQuxO
# 7bN2edgKNAltHIAxH+IOVN3lofvlRxCtZJj/UBYufL8FIXrilUEnacOTj5XJjdib
# Ia4NXJzwoq6GaIMMai27dmsAHZat8hZ79haDJLmIz2qoRzEvmtzjcT3XAH5iR9HO
# iMm4GPoOco3Boz2vAkBq/2mbluIQqBC0N1AI1sM9MIIGBzCCA++gAwIBAgIKYRZo
# NAAAAAAAHDANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkw
# FwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMDcwNDAzMTI1MzA5WhcNMjEwNDAz
# MTMwMzA5WjB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCfoWyx39tIkip8ay4Z4b3i48WZUSNQrc7dGE4kD+7R
# p9FMrXQwIBHrB9VUlRVJlBtCkq6YXDAm2gBr6Hu97IkHD/cOBJjwicwfyzMkh53y
# 9GccLPx754gd6udOo6HBI1PKjfpFzwnQXq/QsEIEovmmbJNn1yjcRlOwhtDlKEYu
# J6yGT1VSDOQDLPtqkJAwbofzWTCd+n7Wl7PoIZd++NIT8wi3U21StEWQn0gASkdm
# EScpZqiX5NMGgUqi+YSnEUcUCYKfhO1VeP4Bmh1QCIUAEDBG7bfeI0a7xC1Un68e
# eEExd8yb3zuDk6FhArUdDbH895uyAc4iS1T/+QXDwiALAgMBAAGjggGrMIIBpzAP
# BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBQjNPjZUkZwCu1A+3b7syuwwzWzDzAL
# BgNVHQ8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwgZgGA1UdIwSBkDCBjYAUDqyC
# YEBWJ5flJRP8KuEKU5VZ5KShY6RhMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eYIQea0WoUqgpa1Mc1j0BxMuZTBQBgNVHR8E
# STBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsG
# AQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFJvb3RDZXJ0LmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0B
# AQUFAAOCAgEAEJeKw1wDRDbd6bStd9vOeVFNAbEudHFbbQwTq86+e4+4LtQSooxt
# YrhXAstOIBNQmd16QOJXu69YmhzhHQGGrLt48ovQ7DsB7uK+jwoFyI1I4vBTFd1P
# q5Lk541q1YDB5pTyBi+FA+mRKiQicPv2/OR4mS4N9wficLwYTp2OawpylbihOZxn
# LcVRDupiXD8WmIsgP+IHGjL5zDFKdjE9K3ILyOpwPf+FChPfwgphjvDXuBfrTot/
# xTUrXqO/67x9C0J71FNyIe4wyrt4ZVxbARcKFA7S2hSY9Ty5ZlizLS/n+YWGzFFW
# 6J1wlGysOUzU9nm/qhh6YinvopspNAZ3GmLJPR5tH4LwC8csu89Ds+X57H2146So
# dDW4TsVxIxImdgs8UoxxWkZDFLyzs7BNZ8ifQv+AeSGAnhUwZuhCEl4ayJ4iIdBD
# 6Svpu/RIzCzU2DKATCYqSCRfWupW76bemZ3KOm+9gSd0BhHudiG/m4LBJ1S2sWo9
# iaF2YbRuoROmv6pH8BJv/YoybLL+31HIjCPJZr2dHYcSZAI9La9Zj7jkIeW1sMpj
# tHhUBdRBLlCslLCleKuzoJZ1GtmShxN1Ii8yqAhuoFuMJb+g74TKIdbrHk/Jmu5J
# 4PcBZW+JC33Iacjmbuqnl84xKf8OxVtc2E0bodj6L54/LlUWa8kTo/0xggSXMIIE
# kwIBATCBkDB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSMw
# IQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQQITMwAAAUCWqe5wVv7M
# BwABAAABQDAJBgUrDgMCGgUAoIGwMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQ1
# zDWNQh5m55u5EfwZbkLKo8jT5TBQBgorBgEEAYI3AgEMMUIwQKAWgBQAUABvAHcA
# ZQByAFMAaABlAGwAbKEmgCRodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUG93ZXJT
# aGVsbCAwDQYJKoZIhvcNAQEBBQAEggEAK3yPgWNSHBwy0j7xL+V1tDGXh2cORefR
# d24R7kviaH/ceOKSmArklvZ/tyAdQgyf+Fo16kZPowwA1SppJnjEszwokM1ZbODA
# FTsr5pa1xnYYiAfAYqPvyPIsHPI2/pwSyQzNFFcgLmFI/dt8nv9oKKojiT1q5+jb
# sfKDGt6+znZdtRAFB3ybdpNusxkBHq5oDO79j+T1OeDSwjnoE/CM4ekVQTRl2GK4
# pUKZ4WYwPaXt8qvnqah+4ekLyktCqq3bjtRF0bJJ+9CrFdOMqULAh1LdidoXrb00
# GxbcPqF9AvjLIydFNCNYO1yZ42myTBs+97SrgEZZg6UnXYkDk/VqqKGCAigwggIk
# BgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0ECEzMAAAC4GDyo1wN7fYIAAAAAALgwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJ
# AzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE3MDUyNDE3MjcwNVowIwYJ
# KoZIhvcNAQkEMRYEFEHiZpysr4Z6Ddkgvtaqmc/w96ddMA0GCSqGSIb3DQEBBQUA
# BIIBAB9nMxPLB5aU93239n8Vu6hVM543arEXEsEkw7fpmWB0tDDGWuwKGAZF84ML
# vD766k8RIrbOYJz1YAa4vVyL+bzO5LdneooS429nWZuVlxztutj2y3tFhOpldoTQ
# 1N/0baI4cdB5KhSPFdIcDWi3+cp+LEG3PKvB/oQeh1xECQm3AyPRPe0hc9MjiE2g
# aWohdcycOKteNWQfEDgZ6bGErP/rJn/1nCui31DzluaY1fmZSbVYCy1T1XxOeb2Q
# JSdulLclC7fOAGtQ+/XgoQy2UcAgSPA1HpeNPwng9oqEsLE8T+fa2HNuspdIKePx
# K5vL5pQjIiTIusRcv6RAVu5EkJg=
# SIG # End signature block