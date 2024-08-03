# Install the module on demand
If (-not (Get-Module -ErrorAction Ignore -ListAvailable PSParseHTML)) {
    Write-Verbose "Installing PSParseHTML module for the current user..."
    Install-Module -Scope CurrentUser PSParseHTML -ErrorAction Stop
}

$baseUrl = 'https://versii.com/politics/page'
$folderName = 'Zubchenko'
$basePath = "$PSScriptRoot/$folderName/EPUB"
$itemsPath = "$PSScriptRoot/items.xml"

# Clear the folder
if (Test-Path -LiteralPath "$PSScriptRoot/$folderName") {
    Remove-Item -Path "$PSScriptRoot/$folderName" -Recurse
}
if (Test-Path $itemsPath) {
    Remove-Item -Path $itemsPath
}
if (Test-Path "$PSScriptRoot/$folderName.epub") {
    Remove-Item -Path "$PSScriptRoot/$folderName.epub"
}

# Create the folder structure
New-Item -Path $PSScriptRoot -Name $folderName -ItemType "directory"
New-Item -Path "$PSScriptRoot/$folderName" -Name "META-INF" -ItemType "directory"
New-Item -Path "$PSScriptRoot/$folderName" -Name "EPUB" -ItemType "directory"
New-Item -Path $basePath -Name "xhtml" -ItemType "directory"
New-Item -Path $basePath -Name "css" -ItemType "directory"
New-Item -Path $basePath -Name "img" -ItemType "directory"

# Create the mimetype file and copy files
Set-Content -Path "$PSScriptRoot/$folderName/mimetype" -Value 'application/epub+zip' 
Copy-Item "$PSScriptRoot/container.xml" -Destination "$PSScriptRoot/$folderName/META-INF"
Copy-Item "$PSScriptRoot/style.css" -Destination "$basePath/css"
Copy-Item "$PSScriptRoot/titlePage.xhtml" -Destination "$basePath/xhtml"

$id = 0
$items = [System.Collections.ArrayList]::new()
for ($i = 2; $i -lt 3; $i++) {
    #135
    $url = "$baseUrl/$i/"
    $htmlDom = ConvertFrom-Html -Url $url
    $jetPosts = $htmlDom.SelectNodes('//div[@class="jet-posts__inner-content"]') | Where-Object {
        $divAuthor = $_.SelectSingleNode('div[@class="jet-title-fields"]/div/div[@class="jet-title-fields__item-value"]')
        $divAuthor.InnerText -eq 'Александр Зубченко'
    }
    
    foreach ($post in $jetPosts) {
        $header = $post.SelectSingleNode('h4[@class="entry-title"]/a');
        $divAuthor = $post.SelectSingleNode('div[@class="jet-title-fields"]/div/div[@class="jet-title-fields__item-value"]')
        $time = $post.SelectSingleNode('div[@class="post-meta"]/span/a/time')
        $arrUrl = $header.Attributes['href'].Value.Split('/')
        $name = $arrUrl[$arrUrl.Length - 2]
        $id++
        $item = [PSCustomObject]@{
            Id        = $id
            Author    = $divAuthor.InnerText
            Title     = $header.InnerText
            Url       = $header.Attributes['href'].Value
            DateTime  = $time.Attributes['datetime'].Value
            FileName  = "$name.xhtml"
            ImageName = ""
            Year      = $time.Attributes['datetime'].Value.Split('-')[0]
            Month     = $time.Attributes['datetime'].Value.Split('-')[1]
        }

        [void]$items.Add($item)

        $itemDom = ConvertFrom-Html -Url $item.Url
        $h1 = $itemDom.SelectSingleNode('//h1[@class="elementor-heading-title elementor-size-default"]')       
        $ps = $itemDom.SelectNodes('//div[@class="elementor-shortcode"]/p')
        $img = $itemDom.SelectSingleNode('//img[@class="main-thumb-text wp-post-image"]')
        if ($null -ne $img) {
            $imgName = $item.FileName.Replace('.xhtml', '.jpg')
            Invoke-WebRequest $img.Attributes["src"].Value -OutFile "$basePath/img/$imgName"
            $img.Attributes["src"].Value = "../img/$imgName" 
            $item.ImageName = $imgName
        }
        
        $templateDom = New-Object System.Xml.XmlDocument
        $templateDom.Load("$PSScriptRoot/PageTemplate.xhtml")
        $nsmgr = New-Object System.Xml.XmlNamespaceManager($templateDom.NameTable)
        $nsmgr.AddNamespace("xhtml", "http://www.w3.org/1999/xhtml")
        $title = $templateDom.SelectSingleNode('//xhtml:title', $nsmgr)
        $title.InnerText = $item.Title
        $body = $templateDom.SelectSingleNode('//xhtml:body', $nsmgr)
        $refChild = $body.ChildNodes[0];
        $h1Node = $templateDom.CreateDocumentFragment()
        $h1Node.InnerXml = $h1.OuterHtml.Replace('<h1', '<h1 xmlns="http://www.w3.org/1999/xhtml"')
        $body.InsertBefore($h1Node, $refChild);
        $date = $item.DateTime.Split('T')[0]
        $dateDiv = $templateDom.SelectSingleNode('//xhtml:div[@class="post-meta"]', $nsmgr)
        $dateDiv.InnerXml = "Дата публикации: $date <a xmlns='http://www.w3.org/1999/xhtml' href='nav.xhtml'>вернуться к содержанию</a>"
        if ($null -ne $img) {
            $imgNode = $templateDom.CreateDocumentFragment()
            $imgNode.InnerXml = $img.OuterHtml.Replace('<img', '<img xmlns="http://www.w3.org/1999/xhtml"').Replace('>', '/>')
            $refChild.AppendChild($imgNode)
        }

        $psNode = $templateDom.CreateDocumentFragment()
        $psNode.InnerXml = $ps.OuterHtml.Replace('<p', '<p xmlns="http://www.w3.org/1999/xhtml"')
        $refChild.AppendChild($psNode)                
        $fileName = $item.FileName
        $templateDom.Save("$basePath/xhtml/$fileName")      
    }    
}

ConvertTo-Xml -InputObject $items -As "String" -NoTypeInformation | Set-Content -Path $itemsPath

$xslt = New-Object System.Xml.Xsl.XslCompiledTransform

$xslt.Load("$PSScriptRoot/nav.xslt")
$xslt.Transform($itemsPath, "$basePath/xhtml/nav.xhtml")

$xslt.Load("$PSScriptRoot/package.xslt")
$xslt.Transform($itemsPath, "$basePath/package.opf")

# Create the epub file
Compress-Archive -Path "$PSScriptRoot/$folderName" -DestinationPath "$PSScriptRoot/$folderName.epub" -CompressionLevel Optimal

# Clear the folder
if (Test-Path -LiteralPath "$PSScriptRoot/$folderName") {
    Remove-Item -Path "$PSScriptRoot/$folderName" -Recurse
}
if (Test-Path $itemsPath) {
    Remove-Item -Path $itemsPath
}