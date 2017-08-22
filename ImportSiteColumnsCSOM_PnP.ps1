 Param(
 [Parameter(Mandatory=$true)]
 [string]$SiteUrl,
 [Parameter(Mandatory=$false)]
 [string]$XMLTermsFileName = "SiteColumns.xml"
 )

 Set-Location $PSScriptRoot

 function LoadAndConnectToSharePoint($url)
 {
  Add-Type -Path "..\SharePoint Assemblies\Microsoft.SharePoint.Client.dll"
  Add-Type -Path "..\SharePoint Assemblies\Microsoft.SharePoint.Client.Runtime.dll"
  Add-Type -Path "..\SharePoint Assemblies\Microsoft.SharePoint.Client.Taxonomy.dll"
  
  ##Using PnP library
  Connect-SPOnline -Url $SiteUrl #-CurrentCredentials
  $spContext =  Get-SPOContext
  return $spContext
}

$Context = LoadAndConnectToSharePoint  $SiteUrl
#http://dev-sp-001a:1214/ContentTypeHub

$xmlFilePath = (get-location).ToString() + "\$XMLTermsFileName"

 #Get XML file exported
[xml]$fieldsXML = Get-Content($xmlFilePath)

   $fieldsXML.Fields.Field | ForEach-Object {
   $field = Get-SPOField  -Identity $_.ID -ErrorAction SilentlyContinue
   if($field -eq $null)
    {
     $fieldName = $_.Name   
  ##remove Version attribute from XML as throwing message "The object has been updated by another user since it was last fetched"
     $_.RemoveAttribute("Version")
      if($_.Type -eq 'TaxonomyFieldTypeMulti' -or $_.Type -eq 'TaxonomyFieldType')
      {
         $termSetIdEle= $_.Customization.ArrayOfProperty.Property|?{$_.Name -eq "TermSetId"}         
         $termId= [Guid]$termSetIdEle.Value.InnerText; 

         $termStoreIdEle= $_.Customization.ArrayOfProperty.Property|?{$_.Name -eq "SspId"}
         
         $ChildNodes = $_.ChildNodes;
         foreach($childNode in $ChildNodes) {$childNode.ParentNode.RemoveChild($childNode)}
      }

      Add-SPOFieldFromXml -FieldXml $_.OuterXml
      $field = Get-SPOField  -Identity $_.ID
        if($_.Type -eq 'TaxonomyFieldTypeMulti' -or $_.Type -eq 'TaxonomyFieldType')
        {
          try
          {
          ##Retrieve as Taxonomy Field
           $taxonomyField= [Microsoft.SharePoint.Client.ClientContext].GetMethod("CastTo").MakeGenericMethod([Microsoft.SharePoint.Client.Taxonomy.TaxonomyField]).Invoke($Context, $field)
          
           $taxonomyField.SspId = [Guid]$termStoreIdEle.Value.InnerText;   
          
           $taxonomyField.TermSetId = $termId;
           
           $taxonomyField.Update();
          
           $Context.ExecuteQuery();
         
          }
          catch
          {
           Write-Host "Error associating field $fieldName to term $termId Exception is $_.Exception.Message" -foregroundColor "Red" 
           return
          }  
        }  
    }
  }