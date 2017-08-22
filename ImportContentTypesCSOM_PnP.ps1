 Param(
 [Parameter(Mandatory=$true)]
 [string]$SiteUrl,
 [Parameter(Mandatory=$false)]
 [string]$XMLCTFileName = "SiteContentTypes.xml"
 )

Set-Location $PSScriptRoot

function LoadAndConnectToSharePoint($url)
{
  ##Using PnP library
  Connect-SPOnline -Url $SiteUrl -CurrentCredentials
  $spContext =  Get-SPOContext
  return $spContext
}

LoadAndConnectToSharePoint $SiteUrl

 #Get XML file exported
$xmlFilePath = (get-location).ToString() + "\$XMLCTFileName"
[xml]$CTXML = Get-Content($xmlFilePath)

$CTXML.ContentTypes.ContentType | ForEach-Object {

    #check if content type exists
    $spContentType = Get-SPOContentType -Identity $_.Name
    if( $spContentType -eq $null)
    {
    #Create Content Type object inheriting from parent
       
    $spContentType = Add-SPOContentType -ContentTypeId $_.ID -Group $_.Group -Name $_.Name -Description $_.Description
      
    $_.Fields.Field  | ForEach-Object {
          #Create a field link for the Content Type by getting an existing column
          #-Required $Required -Hidden $Hidden 
          if($_.Required -eq "TRUE" -and $_.Hidden -eq "TRUE") 
          {
            $spFieldLink =  Add-SPOFieldToContentType -Field $_.Name -ContentType $spContentType.Name -Required -Hidden
          }
          elseif($_.Hidden -eq "TRUE" -and $_.Required -eq "FALSE") 
          {
            $spFieldLink =  Add-SPOFieldToContentType -Field $_.Name -ContentType $spContentType.Name -Hidden
          }
          elseif($_.Hidden -eq "FALSE" -and $_.Required -eq "TRUE")
          {
           $spFieldLink =  Add-SPOFieldToContentType -Field $_.Name -ContentType $spContentType.Name -Required
          }
          else
          {
           $spFieldLink =  Add-SPOFieldToContentType -Field $_.Name -ContentType $spContentType.Name
          }       
    }
    write-host "Content type" $spContentType.Name "has been created"
   }
}