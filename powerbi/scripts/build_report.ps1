# Generates the report pages (PBIR JSON) of powerbi/rfm_dashboard.pbip. Close Power BI Desktop before running.
param([string]$Report = (Join-Path $PSScriptRoot '..\rfm_dashboard.Report'),
      [string]$Theme  = (Join-Path $PSScriptRoot '..\theme.json'),
      [ValidateSet('ivory', 'white')][string]$Surface = 'ivory')
$ErrorActionPreference = 'Stop'
if (Get-Process PBIDesktop -ErrorAction SilentlyContinue) { throw 'Close Power BI Desktop first: it overwrites these files on save.' }
$def = Join-Path $Report 'definition'
# Page and panel colour: ivory = one uniform warm surface; white = plain white page and panels
$SurfaceHex = @{ ivory = '#F8F5EF'; white = '#FFFFFF' }[$Surface]
$VS  = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.0.0/schema.json'
$PS  = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json'

# ---------- helpers ----------
function L($v)    { [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = $v } } } }
function Str($s)  { L ("'" + $s.Replace("'", "''") + "'") }
function Num($n)  { L ("$($n)D") }
function Bool($b) { L ($(if ($b) { 'true' } else { 'false' })) }
function Col($h)  { [ordered]@{ solid = [ordered]@{ color = (Str $h) } } }
function Save($path, $obj) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $obj | ConvertTo-Json -Depth 64 | Set-Content -Path $path -Encoding utf8NoBOM
}
function Pos($x, $y, $w, $h, $z = 1000) { [ordered]@{ x = $x; y = $y; z = $z; height = $h; width = $w; tabOrder = $z } }
function Run($text, $size, $color, [switch]$Bold, $family = 'Segoe UI') {
    $st = [ordered]@{ fontFamily = $family; fontSize = "$($size)pt"; color = $color }
    if ($Bold) { $st.fontWeight = 'bold' }
    [ordered]@{ value = $text; textStyle = $st }
}
function Para($runs, $align = 'left') { [ordered]@{ textRuns = @($runs); horizontalTextAlignment = $align } }
function MeasureF($e, $p) { [ordered]@{ Measure = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Entity = $e } }; Property = $p } } }
function ColumnF($e, $p)  { [ordered]@{ Column  = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Entity = $e } }; Property = $p } } }
function Proj($field, $e, $p, $display = $null) {
    $o = [ordered]@{ field = $field; queryRef = "$e.$p"; nativeQueryRef = $p }
    if ($display) { $o.displayName = $display }
    $o
}
function Visual($page, $name, $pos, $visual) {
    Save (Join-Path $def "pages\$page\visuals\$name\visual.json") ([ordered]@{ '$schema' = $VS; name = $name; position = $pos; visual = $visual })
}
function NoTitle { [ordered]@{ title = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } }) } }

function TextBox($page, $name, $pos, $paras, [switch]$Transparent, $PadTop = $null, $Pad = $null) {
    $v = [ordered]@{
        visualType = 'textbox'
        objects = [ordered]@{ general = @([ordered]@{ properties = [ordered]@{ paragraphs = @($paras) } }) }
        visualContainerObjects = [ordered]@{}
        drillFilterOtherVisuals = $true
    }
    if ($null -ne $Pad) { $v.visualContainerObjects.padding = @([ordered]@{ properties = [ordered]@{ top = (Num $Pad); bottom = (Num $Pad); left = (Num 8); right = (Num 8) } }) }
    if ($PadTop) { $v.visualContainerObjects.padding = @([ordered]@{ properties = [ordered]@{ top = (Num $PadTop) } }) }
    if ($Transparent) { $v.visualContainerObjects.background = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } }) }
    Visual $page $name $pos $v
}

function NavLink($page, $name, $pos, $target) {
    # Invisible button laid over a text tile; teal tint on hover.
    $v = [ordered]@{
        visualType = 'actionButton'
        objects = [ordered]@{
            icon    = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) }; selector = @{ id = 'default' } })
            text    = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) }; selector = @{ id = 'default' } })
            outline = @(foreach ($st in @($null, 'default', 'hover', 'press', 'selected')) { $e = [ordered]@{ properties = [ordered]@{ show = (Bool $false) } }; if ($st) { $e.selector = @{ id = $st } }; $e })
            fill    = @(
                [ordered]@{ properties = [ordered]@{ show = (Bool $true); fillColor = (Col $SurfaceHex); transparency = (Num 100) }; selector = @{ id = 'default' } },
                [ordered]@{ properties = [ordered]@{ fillColor = (Col '#6E1E2B'); transparency = (Num 94) }; selector = @{ id = 'hover' } }
            )
        }
        visualContainerObjects = [ordered]@{
            background = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            title      = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            padding    = @([ordered]@{ properties = [ordered]@{ left = (Num 0); right = (Num 0); top = (Num 0); bottom = (Num 0) } })
            visualLink = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); type = (Str 'PageNavigation'); navigationSection = (Str $target) } })
        }
        drillFilterOtherVisuals = $true
    }
    Visual $page $name $pos $v
}

function Card($page, $name, $pos, $measure, $valueColor = '#2A1E1A', $display = $null) {
    $v = [ordered]@{
        visualType = 'card'
        query = [ordered]@{ queryState = [ordered]@{ Values = [ordered]@{ projections = @(Proj (MeasureF 'analysis_ready' $measure) 'analysis_ready' $measure $display) } } }
        objects = [ordered]@{
            labels = @([ordered]@{ properties = [ordered]@{
                color = (Col $valueColor); fontSize = (Num 18); fontFamily = (Str 'Segoe UI Semibold'); labelDisplayUnits = (Num 1) } })
            categoryLabels = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); color = (Col '#7A6E66'); fontSize = (Num 9) } })
            wordWrap = @([ordered]@{ properties = [ordered]@{ show = (Bool $true) } })
        }
        visualContainerObjects = [ordered]@{
            title   = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            padding = @([ordered]@{ properties = [ordered]@{ left = (Num 8); right = (Num 8); top = (Num 12); bottom = (Num 12) } })
        }
        drillFilterOtherVisuals = $true
    }
    Visual $page $name $pos $v
}

function PageNav($page, $name) {
    $v = [ordered]@{
        visualType = 'pageNavigator'
        objects = [ordered]@{
            fill = @(
                [ordered]@{ properties = [ordered]@{ show = (Bool $true); fillColor = (Col $SurfaceHex); transparency = (Num 0) }; selector = @{ id = 'default' } },
                [ordered]@{ properties = [ordered]@{ fillColor = (Col $SurfaceHex) }; selector = @{ id = 'selected' } },
                [ordered]@{ properties = [ordered]@{ fillColor = (Col '#F3EEE6') }; selector = @{ id = 'hover' } }
            )
            text = @(
                [ordered]@{ properties = [ordered]@{ show = (Bool $true); fontColor = (Col '#7A6E66'); fontSize = (Num 10); fontFamily = (Str 'Segoe UI') }; selector = @{ id = 'default' } },
                [ordered]@{ properties = [ordered]@{ fontColor = (Col '#6E1E2B'); bold = (Bool $true) }; selector = @{ id = 'selected' } }
            )
            outline = @(foreach ($st in @($null, 'default', 'hover', 'press', 'selected')) { $e = [ordered]@{ properties = [ordered]@{ show = (Bool $false) } }; if ($st) { $e.selector = @{ id = $st } }; $e })
        }
        visualContainerObjects = NoTitle
        drillFilterOtherVisuals = $true
    }
    Visual $page $name (Pos 720 0 560 56) $v
}

function Header($page, $title) {
    TextBox $page 'hdrTitle' (Pos 0 0 340 56) @(Para @(Run $title 18 '#2A1E1A' -family 'Segoe UI Semibold'))
    TextBox $page 'hdrNote' (Pos 340 0 380 56) @(Para @(Run 'Data: 1 Dec 2009 – 9 Dec 2011 · GBP · reference date 10 Dec 2011' 9 '#7A6E66') 'right') -PadTop 21
    PageNav $page 'hdrNav'
    $rule = [ordered]@{
        visualType = 'textbox'
        objects = [ordered]@{ general = @([ordered]@{ properties = [ordered]@{ paragraphs = @([ordered]@{ textRuns = @([ordered]@{ value = '' }) }) } }) }
        visualContainerObjects = [ordered]@{
            background = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); color = (Col '#B08A3E'); transparency = (Num 0) } })
            padding    = @([ordered]@{ properties = [ordered]@{ left = (Num 0); right = (Num 0); top = (Num 0); bottom = (Num 0) } })
        }
        drillFilterOtherVisuals = $true
    }
    Visual $page 'hdrRule' (Pos 0 56 1280 2 3000) $rule
}

function Page($id, $display) {
    Save (Join-Path $def "pages\$id\page.json") ([ordered]@{ '$schema' = $PS; name = $id; displayName = $display; displayOption = 'FitToPage'; height = 720; width = 1280 })
}

# ---------- theme ----------
$res = Join-Path $Report 'StaticResources\RegisteredResources'
New-Item -ItemType Directory -Force $res | Out-Null
$th = [IO.File]::ReadAllText($Theme) -replace '#FFFFFF', $SurfaceHex -replace '#F8F5EF', $SurfaceHex
if ($Surface -eq 'ivory') { $th = $th -replace '#FBF9F5', '#F1EBE1' }
[IO.File]::WriteAllText((Join-Path $res 'RFM_Retention.json'), $th, (New-Object Text.UTF8Encoding $false))
$rj = Get-Content (Join-Path $def 'report.json') -Raw | ConvertFrom-Json -AsHashtable
$rj.themeCollection.customTheme = [ordered]@{ name = 'RFM_Retention.json'; reportVersionAtImport = $rj.themeCollection.baseTheme.reportVersionAtImport; type = 'RegisteredResources' }
$rj.resourcePackages = @($rj.resourcePackages | Where-Object { $_.name -ne 'RegisteredResources' }) + @(
    [ordered]@{ name = 'RegisteredResources'; type = 'RegisteredResources'; items = @([ordered]@{ name = 'RFM_Retention.json'; path = 'RFM_Retention.json'; type = 'CustomTheme' }) })
Save (Join-Path $def 'report.json') $rj

# ---------- pages ----------
$homeId = 'e53cdbd248e4b8dd2dc3'; $ov = 'b0e1a2c3d4e5f6071829'; $rfm = 'c1f2a3b4c5d6e7f80912'
Remove-Item (Join-Path $def "pages\$homeId\visuals") -Recurse -Force -ErrorAction SilentlyContinue
Page $homeId 'Home'; Page $ov 'Business Overview'; Page $rfm 'RFM Analysis'
Save (Join-Path $def 'pages\pages.json') ([ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json'
    pageOrder = @($homeId, $ov, $rfm); activePageName = $homeId })

Header $homeId 'Home'
foreach ($p in @(@($ov, 'Business Overview'), @($rfm, 'RFM Analysis'))) {
    Header $p[0] $p[1]
}

# ---------- Home ----------
TextBox $homeId 'homeTitle' (Pos 24 80 600 120) -Transparent @(
    (Para @(Run 'Customer Value & Retention Analysis' 24 '#2A1E1A' -family 'Segoe UI Semibold')),
    (Para @(Run 'RFM segmentation of 5,878 customers and £17.4M of revenue (Dec 2009 – Dec 2011): where value is concentrated, which customers are lapsing, and the recommended action for each segment.' 12 '#7A6E66')))

TextBox $homeId 'navOverviewTile' (Pos 24 216 600 80) @(
    (Para @(Run 'Business Overview  →' 14 '#2A1E1A' -family 'Segoe UI Semibold')),
    (Para @(Run 'Revenue, orders and customers by month, quarter, year and country' 10 '#7A6E66')))
NavLink $homeId 'navOverviewBtn' (Pos 24 216 600 80 2000) $ov

TextBox $homeId 'navRfmTile' (Pos 24 312 600 80) @(
    (Para @(Run 'RFM Analysis  →' 14 '#2A1E1A' -family 'Segoe UI Semibold')),
    (Para @(Run 'Segments, churn and where value is at risk' 10 '#7A6E66')))
NavLink $homeId 'navRfmBtn' (Pos 24 312 600 80 2000) $rfm

Card $homeId 'kpiRevenue'   (Pos 24  408 150 120) 'Total Revenue (£)' '#2A1E1A' 'Customer-attributed revenue'
Card $homeId 'kpiCustomers' (Pos 190 408 116 120) 'Total Customers'
Card $homeId 'kpiChurn'     (Pos 322 408 116 120) 'Churned %' '#D6452B' 'Churned (as of 10 Dec 2011)'
Card $homeId 'kpiChampions' (Pos 454 408 170 120) 'Champions Revenue Share %' '#2A1E1A' 'Champions share of revenue'

TextBox $homeId 'dataNote' (Pos 24 560 1232 120) -Transparent @(
    (Para @((Run 'Source: ' 9 '#4A3F38' -Bold), (Run 'Online Retail II, UCI Machine Learning Repository, donated by Daqing Chen, CC BY 4.0.' 9 '#4A3F38'))),
    (Para @((Run 'Cleaning: ' 9 '#4A3F38' -Bold), (Run '1,067,371 raw rows → 779,425 customer purchase lines. Excluded: duplicates, cancellations, adjustments, zero/negative lines, and rows without a Customer ID (15.1% of purchase revenue).' 9 '#4A3F38'))),
    (Para @((Run 'Scope: ' 9 '#4A3F38' -Bold), (Run 'revenue and customer figures cover customer-attributed purchases only. Churn is a snapshot at 10 Dec 2011: with a date filter, Churned % is the share of that period''s buyers who are churned now.' 9 '#4A3F38'))),
    (Para @(Run "Methodology inspired by Mansi Goel's public tutorial; rebuilt independently in PostgreSQL and Python." 9 '#7A6E66')))

# Glossary table
$seg = ColumnF 'segment_rules' 'segment'
$tbl = [ordered]@{
    visualType = 'tableEx'
    query = [ordered]@{
        queryState = [ordered]@{ Values = [ordered]@{ projections = @(
            (Proj $seg 'segment_rules' 'segment' 'Segment'),
            (Proj (ColumnF 'segment_rules' 'R Range') 'segment_rules' 'R Range' 'R'),
            (Proj (ColumnF 'segment_rules' 'F Range') 'segment_rules' 'F Range' 'F'),
            (Proj (ColumnF 'segment_rules' 'meaning') 'segment_rules' 'meaning' 'Meaning')) } }
        sortDefinition = [ordered]@{ sort = @([ordered]@{ field = $seg; direction = 'Ascending' }); isDefaultSort = $true }
    }
    objects = [ordered]@{
        values = @(
            [ordered]@{ properties = [ordered]@{ wordWrap = (Bool $true); fontSize = (Num 10) } },
            [ordered]@{ properties = [ordered]@{ fontColor = [ordered]@{ solid = [ordered]@{ color = [ordered]@{ expr = [ordered]@{ Aggregation = [ordered]@{
                        Expression = (ColumnF 'segment_rules' 'Segment Colour'); Function = 3 } } } } } }
                        selector = [ordered]@{ data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } }); metadata = 'segment_rules.segment' } })
        columnHeaders = @([ordered]@{ properties = [ordered]@{ wordWrap = (Bool $true) } })
        total = @([ordered]@{ properties = [ordered]@{ totals = (Bool $false) } })
        columnWidth = @(
            [ordered]@{ properties = [ordered]@{ value = (Num 130) }; selector = [ordered]@{ metadata = 'segment_rules.segment' } },
            [ordered]@{ properties = [ordered]@{ value = (Num 48) };  selector = [ordered]@{ metadata = 'segment_rules.R Range' } },
            [ordered]@{ properties = [ordered]@{ value = (Num 48) };  selector = [ordered]@{ metadata = 'segment_rules.F Range' } },
            [ordered]@{ properties = [ordered]@{ value = (Num 330) }; selector = [ordered]@{ metadata = 'segment_rules.meaning' } })
    }
    visualContainerObjects = [ordered]@{
        title = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); text = (Str 'Segments (rules evaluated top-down, first match wins)') } })
    }
    drillFilterOtherVisuals = $true
}
Visual $homeId 'glossaryTable' (Pos 656 80 600 284) $tbl

TextBox $homeId 'definitions' (Pos 656 364 600 164) @(
    (Para @(Run 'Definitions' 11 '#2A1E1A' -family 'Segoe UI Semibold')),
    (Para @((Run 'Recency: ' 10 '#4A3F38' -Bold), (Run 'days since last purchase, to 10 Dec 2011.' 10 '#4A3F38'))),
    (Para @((Run 'Frequency: ' 10 '#4A3F38' -Bold), (Run 'distinct invoices.' 10 '#4A3F38'))),
    (Para @((Run 'Monetary: ' 10 '#4A3F38' -Bold), (Run 'total revenue (£).' 10 '#4A3F38'))),
    (Para @((Run 'R/F/M score: ' 10 '#4A3F38' -Bold), (Run 'quintiles 1–5, 5 = best; recency reversed.' 10 '#4A3F38'))),
    (Para @((Run 'Churned: ' 10 '#4A3F38' -Bold), (Run 'no purchase in the 90 days before 10 Dec 2011.' 10 '#4A3F38'))),
    (Para @((Run 'AOV: ' 10 '#4A3F38' -Bold), (Run 'revenue ÷ orders.' 10 '#4A3F38'))))

. (Join-Path $PSScriptRoot 'build_overview.ps1')
. (Join-Path $PSScriptRoot 'build_rfm.ps1')
Get-ChildItem $def -Recurse -File | ForEach-Object { $_.FullName.Substring($def.Length + 1) }












