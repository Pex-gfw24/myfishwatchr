------------------------------------------------------------
-- Query - Fishing effort aggregated to 0.1° resolution
--
-- author: Cian Luck
-- date: 27 June 2024
------------------------------------------------------------

WITH

  ----------------------------------------------------------
  -- Define area of interest
  ----------------------------------------------------------
    aoi AS (
    SELECT
      ST_GEOGFROMTEXT( "MULTIPOLYGON ((({bbox[[1,1]]} {bbox[[1,4]]}, {bbox[[1,2]]} {bbox[[1,4]]}, {bbox[[1,2]]} {bbox[[1,3]]}, {bbox[[1,1]]} {bbox[[1,3]]}, {bbox[[1,1]]} {bbox[[1,4]]})))"  ) AS polygon
	  ),

  ----------------------------------------------------------
  -- Get the list of active fishing vessels
  ----------------------------------------------------------
  fishing_vessels AS (
   SELECT
    ssvid,
    vessel_id,
    year,
    gfw_best_flag AS best_flag,
    best_vessel_class
  FROM
  -- IMPORTANT: change below to most up to date table
    `pipe_ais_v3_published.product_vessel_info_summary`
  WHERE
    prod_shiptype = "fishing"
  ),

  ----------------------------------------------------------
  -- This subquery fishing query the pipe 3 research messages table
  -- to get all messages by fishing vessels in the time range in the AOI #!
  ----------------------------------------------------------
  fishing AS (
  SELECT
    ssvid,
    vessel_id,
    -- lon,
    -- lat,
    FLOOR(lat * 10) as lat_bin,
    FLOOR(lon * 10) as lon_bin,
    EXTRACT(date FROM timestamp) as date,
    EXTRACT(year FROM timestamp) as year,
    hours,
    nnet_score,
    night_loitering,
    eez
  FROM
    `pipe_ais_v3_published.messages`, aoi
  LEFT JOIN UNNEST(regions.eez) AS eez
  WHERE
  -- Restrict query to specific time range
  -- in this case we want the date range of the patrol period
  -- over the last three years
    ((EXTRACT(MONTH FROM timestamp) = 10 AND EXTRACT(DAY FROM timestamp) >= 21) OR
     (EXTRACT(MONTH FROM timestamp) = 11 AND EXTRACT(DAY FROM timestamp) <= 1)) AND
    EXTRACT(YEAR FROM timestamp) BETWEEN 2021 AND 2023
  --We can always change the date above to suite the questions. We can also do this in R since only the dates are being changed
  --But do NOTE: its good practice to edit queries in BigQuery console when there is extensive changes in the codes
  -- Use spatial join to restrict to aoi
  AND ST_CONTAINS(aoi.polygon, ST_GEOGPOINT(lon, lat))
  -- Use good_segments subquery to only include positions from good segments
  AND clean_segs IS TRUE
  ),

  ----------------------------------------------------------
  -- Filter fishing to just the list of active fishing vessels during
  -- the time period of interest and aoi
  ----------------------------------------------------------
  fishing_filtered AS (
  SELECT *
  FROM fishing
  JOIN fishing_vessels
  -- Only keep positions for fishing vessels active those years
  USING(ssvid, vessel_id, year)
  ),

  ----------------------------------------------------------
  -- Create fishing_hours attribute. Use night_loitering instead of nnet_score as indicator of fishing for squid jiggers
  ----------------------------------------------------------
  fishing_hours_filtered AS (
  SELECT *,
    CASE
      WHEN best_vessel_class = 'squid_jigger' and night_loitering = 1 THEN hours
      WHEN best_vessel_class != 'squid_jigger' and nnet_score > 0.5 THEN hours
      ELSE NULL
    END
    AS fishing_hours
  FROM fishing_filtered
  ),


  ----------------------------------------------------------
  -- This subquery sums fishing hours and converts coordinates back to
  -- decimal degrees
  ----------------------------------------------------------
  fishing_binned AS (
  SELECT
    ssvid,
    best_flag,
    best_vessel_class,
    vessel_id,
    date,
    year,
    -- lon,
    -- lat,
    lat_bin / 10 as lat_bin,
    lon_bin / 10 as lon_bin,
    nnet_score,
    night_loitering,
    eez,
    SUM(hours) as hours,
    SUM(fishing_hours) as fishing_hours
  FROM fishing_hours_filtered
  GROUP BY
    ssvid,
    best_flag,
    best_vessel_class,
    vessel_id,
    date,
    year,
    -- lon,
    -- lat,
    lat_bin,
    lon_bin,
    nnet_score,
    night_loitering,
    eez
  )


----------------------------------------------------------
-- Return fishing data
----------------------------------------------------------
SELECT *
FROM fishing_binned