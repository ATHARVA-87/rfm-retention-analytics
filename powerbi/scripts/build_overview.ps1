# Dot-sourced by build_report.ps1; uses its helpers and $ov / $rfm page ids.

function Src($e) { [ordered]@{ SourceRef = [ordered]@{ Entity = $e } } }
function MExpr($e, $p) { [ordered]@{ expr = (MeasureF $e $p) } }
function Proj2($field) {
    $k = @($field.Keys)[0]; $e = $field[$k].Expression.SourceRef.Entity; $p = $field[$k].Property
    [ordered]@{ field = $field; queryRef = "$e.$p"; nativeQueryRef = $p }
}
function Roles($map) { $q = [ordered]@{}; foreach ($k in $map.Keys) { $q[$k] = [ordered]@{ projections = @($map[$k]) } }; $q }
function Title($text) { @([ordered]@{ properties = [ordered]@{ show = (Bool $true); text = (Str $text) } }) }
function ScopeEq($e, $p, $lit) {
    [ordered]@{ data = @([ordered]@{ scopeId = [ordered]@{ Comparison = [ordered]@{ ComparisonKind = 0
        Left = (ColumnF $e $p); Right = [ordered]@{ Literal = [ordered]@{ Value = $lit } } } } }) }
}
function Fill($hex, $selector = $null) {
    $o = [ordered]@{ properties = [ordered]@{ fill = (Col $hex) } }; if ($selector) { $o.selector = $selector }; $o
}
function TopN($name, $colE, $colP, $mE, $mP, $n) {
    [ordered]@{
        name = $name; field = (ColumnF $colE $colP); type = 'TopN'
        filter = [ordered]@{
            Version = 2
            From = @(
                [ordered]@{ Name = 'subquery'; Type = 2; Expression = [ordered]@{ Subquery = [ordered]@{ Query = [ordered]@{
                    Version = 2
                    From = @([ordered]@{ Name = 'c'; Entity = $colE; Type = 0 }, [ordered]@{ Name = 'm'; Entity = $mE; Type = 0 })
                    Select = @([ordered]@{ Column = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Source = 'c' } }; Property = $colP }; Name = 'field' })
                    OrderBy = @([ordered]@{ Direction = 2; Expression = [ordered]@{ Measure = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Source = 'm' } }; Property = $mP } } })
                    Top = $n } } } },
                [ordered]@{ Name = 'c'; Entity = $colE; Type = 0 })
            Where = @([ordered]@{ Condition = [ordered]@{ In = [ordered]@{
                Expressions = @([ordered]@{ Column = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Source = 'c' } }; Property = $colP } })
                Table = [ordered]@{ SourceRef = [ordered]@{ Source = 'subquery' } } } } })
        }
    }
}
function Chart($page, $name, $pos, $type, $roles, $objects, $title, $sort = $null, $filters = $null, $titleExpr = $null) {
    $q = [ordered]@{ queryState = (Roles $roles) }
    if ($sort) { $q.sortDefinition = [ordered]@{ sort = @($sort); isDefaultSort = $true } }
    $vco = [ordered]@{ title = @(Title $title); subTitle = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } }); spacing = @([ordered]@{ properties = [ordered]@{ spaceAbovePlotArea = (Num 2) } }) }
    if ($titleExpr) { $vco.title = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); text = $titleExpr } }) }
    $vis = [ordered]@{ visualType = $type; query = $q; objects = $objects; visualContainerObjects = $vco; drillFilterOtherVisuals = $true }
    $obj = [ordered]@{ '$schema' = $VS; name = $name; position = $pos; visual = $vis }
    if ($filters) { $obj.filterConfig = [ordered]@{ filters = @($filters) } }
    Save (Join-Path $def "pages\$page\visuals\$name\visual.json") $obj
}
function Slicer($page, $name, $pos, $field, $label, $group, [switch]$Single) {
    $p = Proj2 $field; $p.displayName = $label
    $vis = [ordered]@{
        visualType = 'slicer'
        query = [ordered]@{ queryState = [ordered]@{ Values = [ordered]@{ projections = @($p) } } }
        objects = [ordered]@{
            data = @([ordered]@{ properties = [ordered]@{ mode = (Str 'Dropdown') } })
            selection = @([ordered]@{ properties = [ordered]@{ singleSelect = (Bool ([bool]$Single)); selectAllCheckboxEnabled = (Bool (-not $Single)) } })
            header = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); fontColor = (Col '#7A6E66'); textSize = (Num 9) } })
        }
        visualContainerObjects = [ordered]@{
            title = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            padding = @([ordered]@{ properties = [ordered]@{ top = (Num 4); bottom = (Num 4); left = (Num 10); right = (Num 10) } })
        }
        syncGroup = [ordered]@{ groupName = $group; fieldChanges = $true; filterChanges = $true }
        drillFilterOtherVisuals = $true
    }
    Save (Join-Path $def "pages\$page\visuals\$name\visual.json") ([ordered]@{ '$schema' = $VS; name = $name; position = $pos; visual = $vis })
}
function SlicerBar($page) {
    $x = 24
    foreach ($s in @(
        @('slYear', (ColumnF 'Date' 'Year'), 'Year'),
        @('slQuarter', (ColumnF 'Date' 'Quarter'), 'Quarter'),
        @('slMonth', (ColumnF 'Date' 'Month'), 'Month'),
        @('slCountry', (ColumnF 'customer_rfm' 'country'), 'Country'),
        @('slSegment', (ColumnF 'segment_rules' 'segment'), 'Segment'),
        @('slChurn', (ColumnF 'customer_rfm' 'churn_status'), 'Is Churned'))) {
        Slicer $page $s[0] (Pos $x 64 168 56) $s[1] $s[2] $s[2]
        $x += 184
    }
    $btn = [ordered]@{
        visualType = 'actionButton'
        objects = [ordered]@{
            icon = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) }; selector = @{ id = 'default' } })
            text = @(
                [ordered]@{ properties = [ordered]@{ show = (Bool $true); text = (Str 'Clear filters'); fontColor = (Col '#6E1E2B'); fontSize = (Num 10); fontFamily = (Str 'Segoe UI Semibold') }; selector = @{ id = 'default' } })
            outline = @(foreach ($st in @($null, 'default', 'hover', 'press')) { $e = [ordered]@{ properties = [ordered]@{ show = (Bool $false) } }; if ($st) { $e.selector = @{ id = $st } }; $e })
            fill = @(
                [ordered]@{ properties = [ordered]@{ show = (Bool $true); fillColor = (Col '#FFFFFF'); transparency = (Num 0) }; selector = @{ id = 'default' } },
                [ordered]@{ properties = [ordered]@{ fillColor = (Col '#F3EEE6') }; selector = @{ id = 'hover' } })
        }
        visualContainerObjects = [ordered]@{
            title = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            visualLink = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); type = (Str 'ClearAllSlicers') } })
        }
        drillFilterOtherVisuals = $true
    }
    Save (Join-Path $def "pages\$page\visuals\btnClear\visual.json") ([ordered]@{ '$schema' = $VS; name = 'btnClear'; position = (Pos 1128 64 128 56); visual = $btn })
}

# ---------- Business Overview ----------
Get-ChildItem (Join-Path $def "pages\$ov\visuals") -Directory -ErrorAction SilentlyContinue | Where-Object Name -notlike 'hdr*' | Remove-Item -Recurse -Force
SlicerBar $ov

$x = 24
foreach ($k in @(@('ovRevenue', 'Total Revenue (£)', '#2A1E1A', 'Customer-attributed revenue'), @('ovOrders', 'Orders', '#2A1E1A'), @('ovCustomers', 'Total Customers', '#2A1E1A'),
                 @('ovAov', 'Avg Order Value (£)', '#2A1E1A'), @('ovChurn', 'Churned %', '#D6452B', 'Churned % (as of 10 Dec 2011)'))) {
    Card $ov $k[0] (Pos $x 128 232 76) $k[1] $k[2] $k[3]
    $x += 250
}

# Metric toggle: Button slicer, JSON authored by Power BI Desktop (tpl_toggle.json); only size changes here
$mt = ColumnF 'Metric Toggle' 'Metric Toggle'
$tj = Get-Content (Join-Path $PSScriptRoot 'tpl_toggle.json') -Raw | ConvertFrom-Json -AsHashtable
$tj.position = Pos 24 212 232 40
$tj.visual.visualContainerObjects.padding = @([ordered]@{ properties = [ordered]@{ top = (Num 2); bottom = (Num 2); left = (Num 2); right = (Num 2) } })
Save (Join-Path $def "pages\$ov\visuals\ovToggle\visual.json") $tj

# Monthly trend; Y is the field parameter, expanded to its two measures
$ym = ColumnF 'Date' 'Year Month'
Chart $ov 'ovTrend' (Pos 24 256 808 156) 'lineChart' ([ordered]@{
        Category = @(Proj2 $ym)
        Y = @((Proj2 (MeasureF 'analysis_ready' 'Total Revenue (£)')), (Proj2 (MeasureF 'analysis_ready' 'Total Customers')))
        Tooltips = @((Proj2 (MeasureF 'analysis_ready' 'Revenue MoM %')), (Proj2 (MeasureF 'analysis_ready' 'Orders'))) }) `
    ([ordered]@{
        lineStyles = @([ordered]@{ properties = [ordered]@{ showMarker = (Bool $false); strokeWidth = (Num 2) } })
        dataPoint = @(Fill '#6E1E2B')
        legend = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
        categoryAxis = @([ordered]@{ properties = [ordered]@{ axisType = (Str 'Categorical'); showAxisTitle = (Bool $false); fontSize = (Num 8) } })
        valueAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } }) }) `
    'Monthly trend' ([ordered]@{ field = $ym; direction = 'Ascending' }) $null (MExpr 'Metric Toggle' 'Trend Title')
$tp = Join-Path $def "pages\$ov\visuals\ovTrend\visual.json"
$tj = Get-Content $tp -Raw | ConvertFrom-Json -AsHashtable
$tj.visual.query.queryState.Y.fieldParameters = @([ordered]@{ parameterExpr = $mt; index = 0; length = 2 })
Save $tp $tj

# Quarter comparison
$yr = ColumnF 'Date' 'Year'
Chart $ov 'ovQuarter' (Pos 848 212 408 200) 'clusteredColumnChart' ([ordered]@{
        Category = @(Proj2 (ColumnF 'Date' 'Quarter')); Series = @(Proj2 $yr); Y = @(Proj2 (MeasureF 'analysis_ready' 'Total Revenue (£)')) }) `
    ([ordered]@{
        dataPoint = @((Fill '#DDD6CC' (ScopeEq 'Date' 'Year' '2009L')), (Fill '#8C8580' (ScopeEq 'Date' 'Year' '2010L')), (Fill '#6E1E2B' (ScopeEq 'Date' 'Year' '2011L')))
        categoryAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } })
        valueAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } }) }) `
    'Revenue by quarter and year' ([ordered]@{ field = (ColumnF 'Date' 'Quarter'); direction = 'Ascending' })

# Revenue by country, top 10
$cty = ColumnF 'customer_rfm' 'country'
$rev = MeasureF 'analysis_ready' 'Total Revenue (£)'
Chart $ov 'ovCountry' (Pos 24 428 400 276) 'barChart' ([ordered]@{
        Category = @(Proj2 $cty); Y = @(Proj2 $rev)
        Tooltips = @((Proj2 (MeasureF 'analysis_ready' 'Total Customers')), (Proj2 (MeasureF 'analysis_ready' 'Avg Order Value (£)')), (Proj2 (MeasureF 'analysis_ready' 'Churned %'))) }) `
    ([ordered]@{
        dataPoint = @((Fill '#CFC6BC'), (Fill '#6E1E2B' (ScopeEq 'customer_rfm' 'country' "'United Kingdom'")))
        categoryAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false); fontSize = (Num 9) } })
        valueAxis = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
        labels = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); color = (Col '#7A6E66'); fontSize = (Num 8); labelDisplayUnits = (Num 1000000); labelPrecision = (Num 1) } }) }) `
    'Revenue by country (top 10)' ([ordered]@{ field = $rev; direction = 'Descending' }) `
    (TopN 'topCountry' 'customer_rfm' 'country' 'analysis_ready' 'Total Revenue (£)' 10)

# New vs returning
Chart $ov 'ovNewRet' (Pos 440 428 392 276) 'columnChart' ([ordered]@{
        Category = @(Proj2 (ColumnF 'Date' 'Year Quarter'))
        Y = @((Proj2 (MeasureF 'analysis_ready' 'New Customers')), (Proj2 (MeasureF 'analysis_ready' 'Returning Customers')))
        Tooltips = @(Proj2 (MeasureF 'analysis_ready' 'Returning %')) }) `
    ([ordered]@{
        dataPoint = @((Fill '#B08A3E' ([ordered]@{ metadata = 'analysis_ready.New Customers' })), (Fill '#6E1E2B' ([ordered]@{ metadata = 'analysis_ready.Returning Customers' })))
        categoryAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } })
        valueAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } }) }) `
    'New vs returning customers by quarter' ([ordered]@{ field = (ColumnF 'Date' 'Year Quarter'); direction = 'Ascending' })

# Top 10 customers
$cid = ColumnF 'customer_rfm' 'customer_id'
$pc = Proj2 $cid; $pc.displayName = 'Customer'
$pk = Proj2 $cty; $pk.displayName = 'Country'
$ps = Proj2 (ColumnF 'customer_rfm' 'segment'); $ps.displayName = 'Segment'
$pr = Proj2 $rev; $pr.displayName = 'Revenue'
Chart $ov 'ovTopCust' (Pos 848 428 408 276) 'tableEx' ([ordered]@{
        Values = @($pc, $pk, $ps, (Proj2 (MeasureF 'analysis_ready' 'Orders')), $pr) }) `
    ([ordered]@{
        grid = @([ordered]@{ properties = [ordered]@{ rowPadding = (Num 1) } })
        values = @([ordered]@{ properties = [ordered]@{ fontColor = [ordered]@{ solid = [ordered]@{ color = (MExpr 'analysis_ready' 'Segment Colour') } } }
                    selector = [ordered]@{ data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } }); metadata = 'customer_rfm.segment' } })
        total = @([ordered]@{ properties = [ordered]@{ totals = (Bool $false) } }) }) `
    'Top 10 customers by revenue' ([ordered]@{ field = $rev; direction = 'Descending' }) `
    (TopN 'topCustomer' 'customer_rfm' 'customer_id' 'analysis_ready' 'Total Revenue (£)' 10)







# Captions for partial periods and definitions (shown as visual subtitles)
function SetSubtitle($page, $name, $text) {
    $p = Join-Path $def "pages\$page\visuals\$name\visual.json"
    $j = Get-Content $p -Raw | ConvertFrom-Json -AsHashtable
    $j.visual.visualContainerObjects.subTitle = @([ordered]@{ properties = [ordered]@{
        show = (Bool $true); text = (Str $text); fontColor = (Col '#7A6E66'); fontSize = (Num 8) } })
    Save $p $j
}
TextBox $ov 'ovTrendNote' (Pos 272 212 560 40) -Transparent @(Para @(Run 'Monthly points: Dec 2011 covers 1–9 Dec only, so its drop is partial, not a collapse.' 8 '#7A6E66') 'right') -PadTop 14
SetSubtitle $ov 'ovQuarter' '2009 = December only; Q4 2011 runs to 9 Dec'
SetSubtitle $ov 'ovNewRet' 'New = first purchase since Dec 2009 (data start)'

