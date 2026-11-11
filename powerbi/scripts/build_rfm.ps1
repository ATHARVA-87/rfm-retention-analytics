# Dot-sourced after build_overview.ps1; uses its helpers and $rfm page id.

Get-ChildItem (Join-Path $def "pages\$rfm\visuals") -Directory -ErrorAction SilentlyContinue | Where-Object Name -notlike 'hdr*' | Remove-Item -Recurse -Force
SlicerBar $rfm

function SubCard($page, $name, $pos, $measure) {
    $v = [ordered]@{
        visualType = 'card'
        query = [ordered]@{ queryState = [ordered]@{ Values = [ordered]@{ projections = @(Proj2 (MeasureF 'analysis_ready' $measure)) } } }
        objects = [ordered]@{
            labels = @([ordered]@{ properties = [ordered]@{ color = (Col '#7A6E66'); fontSize = (Num 9); fontFamily = (Str 'Segoe UI') } })
            categoryLabels = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
        }
        visualContainerObjects = [ordered]@{
            title   = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
            padding = @([ordered]@{ properties = [ordered]@{ left = (Num 8); right = (Num 8); top = (Num 0); bottom = (Num 6) } })
        }
        drillFilterOtherVisuals = $true
    }
    Visual $page $name $pos $v
}

# KPI row: main value card + caption card, reading as one panel
$x = 24
foreach ($k in @(
    @('rfChamp', 'Champions Revenue Share %', '#2A1E1A', 'Champions share of revenue', 'Champions Revenue Label'),
    @('rfAtRisk', 'At Risk Customers', '#D6452B', 'At Risk customers', 'At Risk Revenue Label'),
    @('rfLoyal', 'Loyal Churned Customers', '#D6452B', 'Loyal customers past 90 days', 'Loyal Churned Revenue Label'),
    @('rfChurn', 'Churned Customers', '#D6452B', 'Churned customers', 'Churned Revenue Label'))) {
    Card $rfm $k[0] (Pos $x 128 296 44) $k[1] $k[2] $k[3]
    $cj = Join-Path $def "pages\$rfm\visuals\$($k[0])\visual.json"
    $cv = Get-Content $cj -Raw | ConvertFrom-Json -AsHashtable
    $cv.visual.objects.categoryLabels = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } })
    $cv.visual.visualContainerObjects.padding = @([ordered]@{ properties = [ordered]@{ left = (Num 8); right = (Num 8); top = (Num 6); bottom = (Num 0) } })
    Save $cj $cv
    TextBox $rfm "$($k[0])Lbl" (Pos $x 172 296 22) @(Para @(Run $k[3] 9 '#7A6E66') 'center') -Pad 2
    SubCard $rfm "$($k[0])Sub" (Pos $x 194 296 26) $k[4]
    $x += 312
}

$seg = ColumnF 'segment_rules' 'segment'
$noAxisTitle = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false) } })

# Customer share vs revenue share by segment
Chart $rfm 'rfShare' (Pos 24 232 520 236) 'clusteredColumnChart' ([ordered]@{
        Category = @(Proj2 $seg)
        Y = @((Proj2 (MeasureF 'analysis_ready' 'Customer Share %')), (Proj2 (MeasureF 'analysis_ready' 'Revenue Share %'))) }) `
    ([ordered]@{
        dataPoint = @((Fill '#DDD6CC' ([ordered]@{ metadata = 'analysis_ready.Customer Share %' })), (Fill '#6E1E2B' ([ordered]@{ metadata = 'analysis_ready.Revenue Share %' })))
        labels = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); color = (Col '#7A6E66'); fontSize = (Num 7); labelPrecision = (Num 1) } })
        categoryAxis = $noAxisTitle
        valueAxis = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } }) }) `
    'Share of customers vs share of revenue' ([ordered]@{ field = $seg; direction = 'Ascending' })

# R x F grid
$rs = ColumnF 'customer_rfm' 'r_score'; $fs = ColumnF 'customer_rfm' 'f_score'
$pr = Proj2 $rs; $pr.displayName = 'R score'
$pf = Proj2 $fs; $pf.displayName = 'F score'
$tc = MeasureF 'analysis_ready' 'Total Customers'
$segFirst = [ordered]@{ Aggregation = [ordered]@{ Expression = (ColumnF 'customer_rfm' 'segment'); Function = 3 } }
$wild = [ordered]@{ data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } }); metadata = 'analysis_ready.Total Customers' }
Chart $rfm 'rfGrid' (Pos 560 232 336 236) 'pivotTable' ([ordered]@{
        Rows = @($pr); Columns = @($pf); Values = @(Proj2 $tc)
        Tooltips = @([ordered]@{ field = $segFirst; queryRef = 'Min(customer_rfm.segment)'; nativeQueryRef = 'Segment'; displayName = 'Segment' }) }) `
    ([ordered]@{
        values = @([ordered]@{ properties = [ordered]@{
            backColor = [ordered]@{ solid = [ordered]@{ color = [ordered]@{ expr = [ordered]@{ FillRule = [ordered]@{
                Input = $tc
                FillRule = [ordered]@{ linearGradient2 = [ordered]@{
                    min = [ordered]@{ color = [ordered]@{ Literal = [ordered]@{ Value = "'#F3EEE6'" } } }
                    max = [ordered]@{ color = [ordered]@{ Literal = [ordered]@{ Value = "'#6E1E2B'" } } }
                    nullColoringStrategy = [ordered]@{ strategy = [ordered]@{ Literal = [ordered]@{ Value = "'asZero'" } } } } } } } } } }
            fontColor = [ordered]@{ solid = [ordered]@{ color = (MExpr 'analysis_ready' 'RF Cell Font') } } }
            selector = $wild })
        subTotals = @([ordered]@{ properties = [ordered]@{ rowSubtotals = (Bool $false); columnSubtotals = (Bool $false) } })
        grid = @([ordered]@{ properties = [ordered]@{ gridVertical = (Bool $false); gridHorizontal = (Bool $false); rowPadding = (Num 4) } })
        columnHeaders = @([ordered]@{ properties = [ordered]@{ fontSize = (Num 10) } })
        rowHeaders = @([ordered]@{ properties = [ordered]@{ fontSize = (Num 10) } }) }) `
    'Customers by R (rows) × F (columns)' ([ordered]@{ field = $rs; direction = 'Descending' })

# Churn by country, countries with 20+ customers
$cty = ColumnF 'customer_rfm' 'country'
$churnPct = MeasureF 'analysis_ready' 'Churned %'
$minCust = [ordered]@{
    name = 'minCustomers'; field = $tc; type = 'Advanced'
    filter = [ordered]@{ Version = 2
        From = @([ordered]@{ Name = 'a'; Entity = 'analysis_ready'; Type = 0 })
        Where = @([ordered]@{ Condition = [ordered]@{ Comparison = [ordered]@{ ComparisonKind = 2
            Left = [ordered]@{ Measure = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Source = 'a' } }; Property = 'Total Customers' } }
            Right = [ordered]@{ Literal = [ordered]@{ Value = '20L' } } } } }) }
}
Chart $rfm 'rfCountry' (Pos 912 232 344 236) 'barChart' ([ordered]@{
        Category = @(Proj2 $cty); Y = @(Proj2 $churnPct)
        Tooltips = @((Proj2 $tc), (Proj2 (MeasureF 'analysis_ready' 'Revenue from Churned (£)'))) }) `
    ([ordered]@{
        dataPoint = @([ordered]@{ properties = [ordered]@{ fill = [ordered]@{ solid = [ordered]@{ color = (MExpr 'analysis_ready' 'Churn Bar Colour') } } }
                      selector = [ordered]@{ data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } }) } })
        labels = @([ordered]@{ properties = [ordered]@{ show = (Bool $true); color = (Col '#7A6E66'); fontSize = (Num 8); labelPrecision = (Num 1) } })
        categoryAxis = @([ordered]@{ properties = [ordered]@{ showAxisTitle = (Bool $false); fontSize = (Num 9) } })
        valueAxis = @([ordered]@{ properties = [ordered]@{ show = (Bool $false) } }) }) `
    'Churn by country (20+ customers)' ([ordered]@{ field = $churnPct; direction = 'Descending' }) $minCust

# Segment table with action
$cols = @(
    @((Proj2 $seg), 'Segment', 112),
    @((Proj2 $tc), 'Customers', 70),
    @((Proj2 (MeasureF 'analysis_ready' 'Customer Share %')), 'Cust. share', 78),
    @((Proj2 (MeasureF 'analysis_ready' 'Total Revenue (£)')), 'Revenue', 86),
    @((Proj2 (MeasureF 'analysis_ready' 'Revenue Share %')), 'Rev. share', 66),
    @((Proj2 (MeasureF 'analysis_ready' 'Avg Recency (days)')), 'Recency (d)', 78),
    @((Proj2 (MeasureF 'analysis_ready' 'Avg Frequency (invoices)')), 'Frequency', 76),
    @((Proj2 (MeasureF 'analysis_ready' 'Avg Monetary (£)')), 'Monetary', 70),
    @((Proj2 $churnPct), 'Churned %', 84),
    @((Proj2 (ColumnF 'segment_rules' 'Action')), 'Action', 484))
$projs = @(); $widths = @()
foreach ($c in $cols) {
    $p = $c[0]; $p.displayName = $c[1]; $projs += $p
    $widths += [ordered]@{ properties = [ordered]@{ value = (Num $c[2]) }; selector = [ordered]@{ metadata = $p.queryRef } }
}
Chart $rfm 'rfTable' (Pos 24 476 1232 228) 'tableEx' ([ordered]@{ Values = $projs }) `
    ([ordered]@{
        values = @(
            [ordered]@{ properties = [ordered]@{ wordWrap = (Bool $true); fontSize = (Num 9) } },
            [ordered]@{ properties = [ordered]@{ fontColor = [ordered]@{ solid = [ordered]@{ color = (MExpr 'analysis_ready' 'Segment Colour') } } }
                        selector = [ordered]@{ data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } }); metadata = 'segment_rules.segment' } })
        columnHeaders = @([ordered]@{ properties = [ordered]@{ wordWrap = (Bool $true) } })
        columnWidth = $widths
        dataBars = @([ordered]@{ properties = [ordered]@{ positiveColor = (Col '#D6452B'); negativeColor = (Col '#D6452B'); axisColor = (Col '#E8E1D6'); hideText = (Bool $false) }
                     selector = [ordered]@{ metadata = 'analysis_ready.Churned %' } })
        grid = @([ordered]@{ properties = [ordered]@{ rowPadding = (Num 2) } })
        total = @([ordered]@{ properties = [ordered]@{ totals = (Bool $false) } }) }) `
    'Segment summary and recommended action' ([ordered]@{ field = $seg; direction = 'Ascending' })


