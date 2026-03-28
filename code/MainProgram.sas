/* =========================================================================
 * SETUP: ASSIGN LIBRARY AND IMPORT RAW DATA
 * ========================================================================= */


%web_drop_table(GROUP_DM.IMPORTED);


FILENAME REFFILE '/home/u64331503/sasuser.v94/Assignment Group 2/Pakistan Largest Ecommerce Dataset.csv';

PROC IMPORT DATAFILE=REFFILE
	DBMS=CSV
	OUT=GROUP_DM.IMPORTED;
	GETNAMES=YES;
RUN;

PROC CONTENTS DATA=GROUP_DM.IMPORTED; RUN;


%web_open_table(GROUP_DM.IMPORTED);


/* ========================================================================= 
 * EXPLORATORY DATA ANALYSIS (EDA)
 * ========================================================================= */

/*Finding the number of missing values in the ID variables*/
proc means data=GROUP_DM.IMPORTED n nmiss;
    var 'Customer ID'n item_id increment_id;
    title "Audit: Number of Missing Values in Key ID Fields";
run;

/*Finding the frequency of values inside the given variable*/
proc freq data=GROUP_DM.IMPORTED;
    tables var22 var23 var24 payment_method category_name_1 / nocum;
    title "Audit: Content of Suspicious VAR Columns and Text Fields";
run;

/*Finding the description of numerical variables*/
proc means data=group_dm.imported mean median std nmiss min max skew;
	var price grand_total qty_ordered discount_amount;
run;

/*Creating a histogram for the grand_total to evaluate distribution*/
proc sgplot data=group_dm.imported; /*Before transformation*/ 
    histogram grand_total;  
    density grand_total;                   
    title "Distribution of Grand Total";
run;

/*Creating a histogram for the price to evaluate distribution*/
proc sgplot data=group_dm.imported; /*Before transformation*/
    histogram price;  
    density price;                   
    title "Distribution of Prices";
run;

/*Creating a boxplot for price variable to handle outliers*/
proc univariate data=group_dm.imported noprint;
    var price;
    output out=group_dm.boxstats pctlpre=p_ pctlpts=25, 75;
run;

proc sgplot data=group_dm.imported;
    vbox price;
    title "Boxplot of Price";
run;


/* ========================================================================= 
 * DATA CLEANING
 * ========================================================================= */

/* =========================================================================
 * STEP 1: STRUCTURAL CLEANING – DROP JUNK, ENFORCE NON-MISSING IDs
 * ========================================================================= */

data group_dm.cleaned;
    set group_dm.imported;

    /* Drop unused fields which contain no value */
    drop var22 var23 var24 var25 var26 'M-Y'n;

    /* Keep only rows where the IDs are not empty */
    if 'Customer ID'n ne . and item_id ne . and increment_id ne .;
run;

/* =========================================================================
 * VERIFICATION AFTER STRUCTURAL CLEANING
 * ========================================================================= */

/*Checking the irrelevant columns are removed*/
proc contents data=group_dm.cleaned;
    title "Verification: Confirm VAR Columns and 'M-Y' Are Removed";
run;

/*Checking if there are any missing values and all records contain non-null ID*/
proc means data=GROUP_DM.cleaned n nmiss;
    var price qty_ordered grand_total item_id discount_amount 'Customer ID'n increment_id;
    title "Verification: Remaining Missing Values in Main Fields";
run;

/* =========================================================================
 * STEP 2: DEEP CLEANING – FIX TEXT, REMOVE INVALID ROWS, STANDARDIZE CASE
 * ========================================================================= */

data group_dm.cleaned;
    set group_dm.cleaned;

    /* Convert \N to actual missing character values */
    if category_name_1 = "\N" then category_name_1 = "";
    if status          = "\N" then status          = "";

    /* Remove rows with clearly invalid status values according to the data*/
    if status = "cod" then delete;
    
    /* Standardizing case in payment method, category and status*/
    payment_method   = propcase(payment_method);
    category_name_1  = propcase(category_name_1);
    status           = propcase(status);

    /* Apply readable formats to date fields */
    format 'Customer Since'n created_at 'Working Date'n date9.;
run;

/* =========================================================================
 * VERIFICATION AFTER REMOVING INVALID ROWS
 * ========================================================================= */

/*Checking that there are no invalid values inside categorical fields*/
proc freq data=group_dm.cleaned;
    tables payment_method category_name_1 status / nocum;
    title "Audit: Check Text Fields for Inconsistent or Garbage Values";
run;

/* =========================================================================
 * STEP 3: REMOVING ANY DUPLICATE ROWS
 * ========================================================================= */

/*nodupkey ensures there are no repeating pairs of increment id and item id*/
proc sort data=group_dm.cleaned out=group_dm.cleaned nodupkey;
    by increment_id item_id;
run;

/* =========================================================================
 * STEP 4: CLEANING OUTLIER DATA IN PRICES
 * ========================================================================= */

data group_dm.cleaned;
    if _N_ = 1 then set group_dm.boxstats;
    set group_dm.cleaned;

    /* Finding the lower and upper quartile of price variable */
    iqr         = p_75 - p_25;
    lower_limit = p_25 - (1.5 * iqr);
    upper_limit = p_75 + (1.5 * iqr);

    /* Keep reasonably priced items only (remove outliers which are values outside the lower and upper quartile and non-positive price) */
    if price >= lower_limit and price <= upper_limit and price > 0;
    
    drop iqr lower_limit upper_limit p_25 p_75;
run;

/*Checking price and outliers using boxplot*/
proc sgplot data=group_dm.cleaned;
    vbox price;
    title "Boxplot of Price";
run;

/* =========================================================================
 * STEP 5: HANDLING INCONSISTENT DATA
 * ========================================================================= */


DATA GROUP_DM.cleaned;
    SET GROUP_DM.cleaned;

    /* Ensure quantity is numeric for the calculations */
    Qty_Numeric = input(compress(qty_ordered, '$,'), best12.); /*use of temporary variable*/

    /* Manually calculate net total by multiplying price and quantity as well as subtracting the discount amount */
    Net_Calculated_Total = (price * Qty_Numeric) - discount_amount;
    
    /*remove temporary variable to prevent confusion*/
    drop Qty_Numeric;

    LABEL Net_Calculated_Total = "Calculated Net Total (Price * Qty - Discount)";
RUN;

proc sgplot data=GROUP_DM.cleaned;
    title "Data Consistency: Calculated Net Total vs Actual Grand Total";

    /* 45-degree reference line (perfect match) */
    lineparm x=0 y=0 slope=1 /
        lineattrs=(color=gray pattern=solid thickness=2)
        legendlabel="Perfect Match Line";

	/*plotting a scatter plot diagram to compare the expected and existing grand total*/
    scatter x=Net_Calculated_Total y=grand_total /
        markerattrs=(symbol=CircleFilled color=indigo size=5)
        transparency=0.4;

    xaxis label="Calculated Net Total (Price * Quantity - Discount)";
    yaxis label="Actual Grand Total (Dataset)";
    keylegend / location=inside position=bottomright;
run;

/*remove records with unmatching grand total*/
DATA GROUP_DM.CLEANED;
	set GROUP_DM.cleaned;
	if grand_total = Net_Calculated_Total;
run;

proc sgplot data=GROUP_DM.CLEANED;
    title "Data Consistency: Calculated Net Total vs Actual Grand Total";

    /* 45-degree reference line (perfect match) */
    lineparm x=0 y=0 slope=1 /
        lineattrs=(color=gray pattern=solid thickness=2)
        legendlabel="Perfect Match Line";

	/*plotting a scatter plot diagram to compare the expected and existing grand total*/
    scatter x=Net_Calculated_Total y=grand_total /
        markerattrs=(symbol=CircleFilled color=indigo size=5)
        transparency=0.4;

    xaxis label="Calculated Net Total (Price * Quantity - Discount)";
    yaxis label="Actual Grand Total (Dataset)";
    keylegend / location=inside position=bottomright;
run;

/* =========================================================================
 * EDA AFTER DATA CLEANING
 * ========================================================================= */

/*Check for the description of numerical variables*/
proc means data=group_dm.cleaned mean median std nmiss min max skew;
	var price grand_total qty_ordered discount_amount;
	title "Descriptive Statistics for Numeric Variables";
run;

/*Check for the values in categorical variables*/
proc freq data=group_dm.cleaned order=freq;
    tables category_name_1 status payment_method;
    title "Frequency of Categories, Statuses, and Payment Methods";
run;

/*Check for the fields inside the dataset*/
proc contents data=group_dm.cleaned;
run;





/* =========================================================================
 * DATA TRANSFORMATION
 * ========================================================================= */

/* =========================================================================
 * STEP 1: STANDARDIZATION OF VARIABLE NAMES
 * ========================================================================= */

data group_dm.transformed;
    set group_dm.cleaned;

    rename
        'Customer ID'n        = customer_id
        'Customer Since'n     = customer_since
        'Working Date'n       = working_date
        'BI Status'n          = bi_status
        'FY'n                 = fiscal_year
        ' MV'n                = mv
        category_name_1       = category
        increment_id          = order_id
        qty_ordered           = quantity
        status                = order_status
        sales_commission_code = commission_code
        sku                   = sku
        grand_total           = grand_total
        discount_amount       = discount_amount
        price                 = price
        payment_method        = payment_method
        created_at            = created_at
    ;
run;

/* Check renamed structure */
proc contents data=group_dm.transformed;
    title "Renamed Dataset Variables";
run;

/* =========================================================================
 * STEP 2: GENERALIZATION OF PRICE RANGE AND QUANTITY
 * ========================================================================= */

data group_dm.transformed;
set group_dm.transformed;
	/* Price band feature: Low (0 to 500) / Medium (500 to 2500) / High (larger than 2500) */
    length price_range $10;
    if      price < 500   then price_range = "Low";
    else if price < 2500  then price_range = "Medium";
    else                       price_range = "High";
    
    /* Categorizing quantity into: Single (1) / Small Bulk (2 to 5) / Large Builk (more than 5)*/
    if quantity = 1 then qty_group = "Single";
    else if quantity <= 5 then qty_group = "Small Bulk";
    else qty_group = "Large Bulk";
run;

/* Proof of generalization using 10 sample records */
option obs=10; /* Take 10 observations */
proc print data=group_dm.transformed;
var price quantity price_range qty_group;
title "Proof of generalization using 10 sample records";
run;
option obs=max;
    
/* =========================================================================
 * STEP 3: FEATURE EXTRACTION FOR MONTH AND YEAR
 * ========================================================================= */

/*Extracting year, month and quarter from working date variable*/
data group_dm.transformed;
set group_dm.transformed;
    year_num  = year(working_date);
    month_num = month(working_date);
    qtr_num   = qtr(working_date);
run;

/* Proof of feature extraction using 10 sample records */
option obs=10; /* Take 10 observations */
proc print data=group_dm.transformed;
var working_date year_num month_num qtr_num;
title "Proof of generalization using 10 sample records";
run;
option obs=max;

/* =========================================================================
 * STEP 4: SCALING PRICE INTO (IN MILLIONS)
 * ========================================================================= */

/*Dividing the price and grand total in millions and represent them as a new variable*/
data group_dm.transformed;
set group_dm.transformed;
	/*dividing by one million*/
	PriceInMil = price/1e6; 
	GrandTotalInMil = grand_total/1e6;
run;

/* Proof of scaling using 10 sample records */
option obs=10; /* Take 10 observations */
proc print data=group_dm.transformed;
var price grand_total PriceInMil GrandTotalInMil;
title "Proof of scaling using 10 sample records";
run;
option obs=max;

/* =========================================================================
 * STEP 5: NORMALIZATION
 * ========================================================================= */

proc sgplot data=group_dm.transformed; /*Before transformation*/ 
    histogram grand_total;  
    density grand_total;                   
    title "Distribution of Grand Total";
run;

proc sgplot data=group_dm.transformed; /*Before transformation*/
    histogram price;  
    density price;                   
    title "Distribution of Prices";
run;

/*Log transformation for grand total;*/
data group_dm.transformed;
    set group_dm.transformed;
    log_grand_total = log(grand_total + 1);
run;


proc sgplot data=group_dm.transformed; /*After transformation*/ 
    histogram log_grand_total; 
    density log_grand_total;
    title "Distribution of Grand Total (In Log)";
    xaxis label = "Grand Total (Log)";
run;

/*Use boxcox to model the price distribution*/
proc transreg data=group_dm.transformed;
   model BoxCox(price) = identity(price);
run;
/*shows that the original price variable is already best fit for modelling*/

/* =========================================================================
   EDA AFTER TRANSFORMATION
 * ========================================================================= */

/*Seek for the new variables added during the transformation phase*/
proc contents data=group_dm.transformed;
run;

/*Check for the description of numerical variables such as mean, skewness and missing values if any*/
proc means data=group_dm.transformed mean median std nmiss min max skew;
	var price grand_total quantity discount_amount log_grand_total;
	title "Descriptive Statistics for Numeric Variables";
run;






/* =========================================================================
 * EXPLORATORY DATA ANALYSIS (EDA) - ANALYTICAL
 * ========================================================================= */

/*Create a new variable for pairing month and year*/
data group_dm.transformed;
    set group_dm.transformed;
    MonthYear = put(mdy(Month_num, 1, Year_num), monyy7.);
    format MonthYear monyy7.;
run;

/*Create bar graph to plot pairs of month and year against the sum of grand total*/
proc sgplot data=group_dm.transformed;
    title "Total Sales Trend Over Time";
    /*using vbar for bar graph and statistics is assigned sum of the response*/
    vbar MonthYear / response=GrandTotalInMil stat=sum; 
    xaxis label="Month and Year" discreteorder=data fitpolicy=rotate;
    yaxis label="Grand Total (In Millions)" grid;
run;

/*Plot a scatter plot diagram to see the relationship between discount amount and quantity*/
proc sgplot data=group_dm.transformed;
    scatter x=discount_amount y=quantity /
        markerattrs=(symbol=circlefilled color=purple size=5)
        transparency=0.5;

    reg x=discount_amount y=quantity;

    title "Relationship: Discount Amount vs Quantity Ordered";
    xaxis label="Discount Amount (RM)";
    yaxis label="Quantity Ordered";
run;

/*Plot a scatter plot diagram to see the relationship between price and quantity*/
proc sgplot data=group_dm.transformed;
    scatter x=price y=quantity /
        markerattrs=(symbol=circlefilled color=blue size=5)
        transparency=0.5;
	
    reg x=price y=quantity;

    title "Relationship: Unit Price vs Quantity Ordered";
    xaxis label="Unit Price (RM)";
    yaxis label="Quantity Ordered";
run;

/*Creating a pie chart with percentages to determine the category with most orders*/
proc sgpie data=group_dm.transformed;
	/*variable to be modelled is category where values shown are percentages*/
    pie category / datalabeldisplay=(category percent) 
                          datalabelloc=callout;
    title "Distribution of Product Categories";
run;

/*Create a new variable for pairing quarter and year*/
data group_dm.transformed;
	set group_dm.transformed;
	Quarter = cats(Year, "Q", Qtr_num);
run;

/*Create line graph to plot the trend per quarter against the sum of grand total in the category with most orders*/
proc sgplot data=group_dm.transformed;
	/*Filters the category*/
	where Category = "Men's Fashion";
    title "Revenue Trend: Men's Fashion - Quarter by Quarter";
    /*using vline for line graph and control the thickness and statistics is assigned sum of the response*/
    vline Quarter / response=GrandTotalInMil stat=sum lineattrs=(thickness=2 color=blue); 
    xaxis label="Quarter" discreteorder=data;
    yaxis label="Total Revenue (In Millions)" grid;
run;

/* =========================================================================
 * EXPORTING THE CLEANED AND TRANSFORMED FILE
 * ========================================================================= */

PROC EXPORT DATA=GROUP_DM.TRANSFORMED
    OUTFILE='/home/u64331503/sasuser.v94/Assignment Group 2/final.csv'
    DBMS=CSV
    REPLACE;
RUN;
