"""
Snowflake Forecasting Lab - Cost and Performance Monitoring Dashboard
Streamlit in Snowflake Application

This Streamlit application runs natively in Snowflake and provides interactive 
visualizations for monitoring warehouse performance, cost attribution, and query 
analytics for forecasting workloads.

To deploy: Run the SQL deployment script in streamlit/monitoring/deploy_streamlit.sql
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta

# Page configuration
st.set_page_config(
    page_title="Forecasting Lab Monitoring",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for better styling
st.markdown("""
    <style>
    .main-header {
        font-size: 2.5rem;
        font-weight: bold;
        margin-bottom: 1rem;
    }
    .metric-card {
        background-color: #f0f2f6;
        padding: 1rem;
        border-radius: 0.5rem;
        margin-bottom: 1rem;
    }
    </style>
""", unsafe_allow_html=True)

# Get Snowflake session (automatically available in Streamlit in Snowflake)
session = get_active_session()

@st.cache_data(ttl=300)
def fetch_data(query):
    """Execute query and return DataFrame with 5-minute cache"""
    try:
        return session.sql(query).to_pandas()
    except Exception as e:
        st.error(f"Error fetching data: {str(e)}")
        return pd.DataFrame()

def get_warehouse_metrics(days=7):
    """Fetch warehouse utilization metrics"""
    query = f"""
    SELECT
        warehouse_name,
        DATE_TRUNC('hour', start_time) AS hour,
        SUM(credits_used) AS total_credits,
        COUNT(*) AS execution_count
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
    GROUP BY warehouse_name, DATE_TRUNC('hour', start_time)
    ORDER BY hour
    """
    return fetch_data(query)

def get_warehouse_load(days=7):
    """Fetch warehouse load history for queuing detection"""
    query = f"""
    SELECT
        start_time,
        end_time,
        avg_running AS avg_running_queries,
        avg_queued_load AS avg_queued_queries,
        avg_queued_provisioning,
        avg_blocked
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
    ORDER BY start_time
    """
    return fetch_data(query)

def get_cost_by_workload(days=7):
    """Fetch cost attribution by workload type"""
    query = f"""
    WITH tagged_queries AS (
        SELECT
            qh.query_id,
            qh.query_tag,
            qh.total_elapsed_time / 1000 AS execution_time_seconds,
            wmh.credits_used,
            CASE
                WHEN qh.query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
                WHEN qh.query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
                WHEN qh.query_tag LIKE '%WORKLOAD:DATA_PREP%' THEN 'DATA_PREP'
                ELSE 'UNTAGGED'
            END AS workload_type,
            CASE
                WHEN qh.query_tag LIKE '%PATH:ML_FUNCTIONS%' THEN 'ML_FUNCTIONS'
                WHEN qh.query_tag LIKE '%PATH:SNOWPARK_XGBOOST%' THEN 'SNOWPARK_XGBOOST'
                ELSE 'OTHER'
            END AS model_path
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
        LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
            ON qh.warehouse_name = wmh.warehouse_name
            AND DATE_TRUNC('hour', qh.start_time) = DATE_TRUNC('hour', wmh.start_time)
        WHERE qh.warehouse_name = 'SFE_SP_WH'
          AND qh.start_time >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
          AND qh.execution_status = 'SUCCESS'
    )
    SELECT
        workload_type,
        model_path,
        COUNT(DISTINCT query_id) AS query_count,
        SUM(execution_time_seconds) / 3600 AS total_execution_hours,
        SUM(credits_used) AS total_credits
    FROM tagged_queries
    GROUP BY workload_type, model_path
    ORDER BY total_credits DESC
    """
    return fetch_data(query)

def get_query_performance(days=7):
    """Fetch query performance metrics"""
    query = f"""
    SELECT
        query_id,
        query_tag,
        user_name,
        start_time,
        total_elapsed_time / 1000 AS execution_time_seconds,
        queued_overload_time / 1000 AS queue_time_seconds,
        bytes_scanned / POWER(1024, 3) AS gb_scanned,
        rows_produced,
        CASE
            WHEN query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
            WHEN query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
            WHEN query_tag LIKE '%WORKLOAD:DATA_PREP%' THEN 'DATA_PREP'
            ELSE 'OTHER'
        END AS workload_type
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
      AND execution_status = 'SUCCESS'
    ORDER BY total_elapsed_time DESC
    LIMIT 100
    """
    return fetch_data(query)

def get_daily_costs(days=30):
    """Fetch daily cost trends"""
    query = f"""
    SELECT
        DATE_TRUNC('day', start_time) AS date,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
    GROUP BY DATE_TRUNC('day', start_time)
    ORDER BY date
    """
    return fetch_data(query)

def get_cost_params():
    """Fetch cost parameters"""
    query = """
    SELECT param_name, param_value 
    FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS
    """
    df = fetch_data(query)
    if not df.empty:
        return dict(zip(df['PARAM_NAME'], df['PARAM_VALUE']))
    return {'DOLLARS_PER_CREDIT': 3.0, 'SP_WH_MEDIUM_CREDITS_PER_HOUR': 6.0}

# ============================================================================
# MAIN APPLICATION
# ============================================================================

def main():
    st.markdown('<p class="main-header">📊 Forecasting Lab Monitoring Dashboard</p>', unsafe_allow_html=True)
    
    # Sidebar configuration
    st.sidebar.header("Configuration")
    time_window = st.sidebar.selectbox(
        "Time Window",
        options=[7, 14, 30],
        format_func=lambda x: f"Last {x} days",
        index=0
    )
    
    # Fetch cost parameters
    cost_params = get_cost_params()
    dollars_per_credit = cost_params.get('DOLLARS_PER_CREDIT', 3.0)
    
    st.sidebar.markdown("---")
    st.sidebar.markdown(f"**Cost Parameters**")
    st.sidebar.markdown(f"💵 ${dollars_per_credit:.2f} per credit")
    st.sidebar.markdown("---")
    st.sidebar.markdown("**About**")
    st.sidebar.info("This dashboard monitors the SFE_SP_WH warehouse used for forecasting workloads.")
    
    # Create tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        "🏭 Warehouse Performance", 
        "💰 Cost Analytics", 
        "⚡ Query Analysis",
        "💡 Recommendations"
    ])
    
    # ========================================================================
    # TAB 1: WAREHOUSE PERFORMANCE
    # ========================================================================
    with tab1:
        st.header("Warehouse Performance Overview")
        
        # Fetch warehouse metrics
        wh_metrics = get_warehouse_metrics(time_window)
        wh_load = get_warehouse_load(time_window)
        
        if not wh_metrics.empty:
            # Summary metrics
            col1, col2, col3, col4 = st.columns(4)
            
            total_credits = wh_metrics['TOTAL_CREDITS'].sum()
            total_cost = total_credits * dollars_per_credit
            total_executions = wh_metrics['EXECUTION_COUNT'].sum()
            avg_credits_per_hour = wh_metrics['TOTAL_CREDITS'].mean()
            
            with col1:
                st.metric("Total Credits", f"{total_credits:.2f}")
            with col2:
                st.metric("Total Cost", f"${total_cost:.2f}")
            with col3:
                st.metric("Total Executions", f"{int(total_executions):,}")
            with col4:
                st.metric("Avg Credits/Hour", f"{avg_credits_per_hour:.3f}")
            
            st.markdown("---")
            
            # Credit usage over time
            st.subheader("Credit Usage Over Time")
            fig_credits = px.line(
                wh_metrics, 
                x='HOUR', 
                y='TOTAL_CREDITS',
                title='Hourly Credit Consumption',
                labels={'HOUR': 'Time', 'TOTAL_CREDITS': 'Credits Used'}
            )
            fig_credits.update_layout(height=400)
            st.plotly_chart(fig_credits, use_container_width=True)
            
            # Warehouse load analysis
            if not wh_load.empty:
                st.subheader("Warehouse Load & Queuing")
                
                fig_load = go.Figure()
                fig_load.add_trace(go.Scatter(
                    x=wh_load['START_TIME'],
                    y=wh_load['AVG_RUNNING_QUERIES'],
                    name='Running Queries',
                    mode='lines',
                    line=dict(color='green')
                ))
                fig_load.add_trace(go.Scatter(
                    x=wh_load['START_TIME'],
                    y=wh_load['AVG_QUEUED_QUERIES'],
                    name='Queued Queries',
                    mode='lines',
                    line=dict(color='red')
                ))
                fig_load.update_layout(
                    title='Warehouse Load History',
                    xaxis_title='Time',
                    yaxis_title='Query Count',
                    height=400
                )
                st.plotly_chart(fig_load, use_container_width=True)
                
                # Queuing alert
                max_queued = wh_load['AVG_QUEUED_QUERIES'].max()
                if max_queued > 0:
                    st.warning(f"⚠️ Queuing detected! Peak queued queries: {max_queued:.2f}. Consider scaling up warehouse or enabling multi-cluster.")
                else:
                    st.success("✅ No queuing detected. Warehouse is properly sized for current workload.")
        else:
            st.info("No warehouse metrics available for the selected time window. Run some forecasting workloads and wait up to 45 minutes for ACCOUNT_USAGE data.")
    
    # ========================================================================
    # TAB 2: COST ANALYTICS
    # ========================================================================
    with tab2:
        st.header("Cost Analytics & Attribution")
        
        # Fetch cost data
        cost_by_workload = get_cost_by_workload(time_window)
        daily_costs = get_daily_costs(min(time_window, 30))
        
        if not cost_by_workload.empty:
            # Add cost column
            cost_by_workload['ESTIMATED_COST'] = cost_by_workload['TOTAL_CREDITS'] * dollars_per_credit
            
            col1, col2 = st.columns(2)
            
            with col1:
                # Cost by workload type
                st.subheader("Cost by Workload Type")
                workload_summary = cost_by_workload.groupby('WORKLOAD_TYPE').agg({
                    'TOTAL_CREDITS': 'sum',
                    'ESTIMATED_COST': 'sum',
                    'QUERY_COUNT': 'sum'
                }).reset_index()
                
                fig_workload_pie = px.pie(
                    workload_summary,
                    values='ESTIMATED_COST',
                    names='WORKLOAD_TYPE',
                    title='Cost Distribution by Workload'
                )
                st.plotly_chart(fig_workload_pie, use_container_width=True)
            
            with col2:
                # Cost by model path
                st.subheader("Cost by Model Path")
                path_summary = cost_by_workload[cost_by_workload['MODEL_PATH'] != 'OTHER'].groupby('MODEL_PATH').agg({
                    'TOTAL_CREDITS': 'sum',
                    'ESTIMATED_COST': 'sum',
                    'QUERY_COUNT': 'sum'
                }).reset_index()
                
                if not path_summary.empty:
                    fig_path_bar = px.bar(
                        path_summary,
                        x='MODEL_PATH',
                        y='ESTIMATED_COST',
                        title='Cost Comparison: ML Functions vs Snowpark',
                        labels={'ESTIMATED_COST': 'Cost ($)', 'MODEL_PATH': 'Approach'}
                    )
                    st.plotly_chart(fig_path_bar, use_container_width=True)
                else:
                    st.info("No model path data available yet. Run forecasting workloads to see comparison.")
            
            st.markdown("---")
            
            # Detailed breakdown table
            st.subheader("Detailed Cost Breakdown")
            display_df = cost_by_workload[['WORKLOAD_TYPE', 'MODEL_PATH', 'QUERY_COUNT', 'TOTAL_CREDITS', 'ESTIMATED_COST']].copy()
            display_df.columns = ['Workload', 'Model Path', 'Queries', 'Credits', 'Cost ($)']
            display_df['Credits'] = display_df['Credits'].round(4)
            display_df['Cost ($)'] = display_df['Cost ($)'].round(2)
            st.dataframe(display_df, use_container_width=True)
        
        # Daily cost trend
        if not daily_costs.empty:
            st.markdown("---")
            st.subheader("Daily Cost Trend")
            daily_costs['DAILY_COST'] = daily_costs['DAILY_CREDITS'] * dollars_per_credit
            
            fig_trend = px.area(
                daily_costs,
                x='DATE',
                y='DAILY_COST',
                title='Daily Spending Trend',
                labels={'DATE': 'Date', 'DAILY_COST': 'Cost ($)'}
            )
            fig_trend.update_layout(height=400)
            st.plotly_chart(fig_trend, use_container_width=True)
            
            # Spending statistics
            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Average Daily Cost", f"${daily_costs['DAILY_COST'].mean():.2f}")
            with col2:
                st.metric("Peak Daily Cost", f"${daily_costs['DAILY_COST'].max():.2f}")
            with col3:
                projected_monthly = daily_costs['DAILY_COST'].mean() * 30
                st.metric("Projected Monthly", f"${projected_monthly:.2f}")
    
    # ========================================================================
    # TAB 3: QUERY ANALYSIS
    # ========================================================================
    with tab3:
        st.header("Query Performance Analysis")
        
        query_perf = get_query_performance(time_window)
        
        if not query_perf.empty:
            # Top slowest queries
            st.subheader("Slowest Queries")
            top_slow = query_perf.nlargest(10, 'EXECUTION_TIME_SECONDS')
            
            fig_slow = px.bar(
                top_slow,
                x='QUERY_ID',
                y='EXECUTION_TIME_SECONDS',
                color='WORKLOAD_TYPE',
                title='Top 10 Slowest Queries',
                labels={'EXECUTION_TIME_SECONDS': 'Execution Time (s)', 'QUERY_ID': 'Query ID'}
            )
            fig_slow.update_layout(height=400, showlegend=True)
            st.plotly_chart(fig_slow, use_container_width=True)
            
            st.markdown("---")
            
            # Performance by workload type
            st.subheader("Performance by Workload Type")
            perf_summary = query_perf.groupby('WORKLOAD_TYPE').agg({
                'EXECUTION_TIME_SECONDS': ['mean', 'median', 'max'],
                'GB_SCANNED': 'sum',
                'QUERY_ID': 'count'
            }).round(2)
            perf_summary.columns = ['Avg Time (s)', 'Median Time (s)', 'Max Time (s)', 'Total GB Scanned', 'Query Count']
            st.dataframe(perf_summary, use_container_width=True)
            
            st.markdown("---")
            
            # Execution time distribution
            st.subheader("Query Execution Time Distribution")
            fig_dist = px.histogram(
                query_perf,
                x='EXECUTION_TIME_SECONDS',
                color='WORKLOAD_TYPE',
                title='Execution Time Distribution',
                labels={'EXECUTION_TIME_SECONDS': 'Execution Time (s)'},
                nbins=30
            )
            fig_dist.update_layout(height=400)
            st.plotly_chart(fig_dist, use_container_width=True)
            
            # Queue analysis
            queued_queries = query_perf[query_perf['QUEUE_TIME_SECONDS'] > 0]
            if not queued_queries.empty:
                st.warning(f"⚠️ {len(queued_queries)} queries experienced queuing delays")
                st.dataframe(
                    queued_queries[['QUERY_ID', 'WORKLOAD_TYPE', 'EXECUTION_TIME_SECONDS', 'QUEUE_TIME_SECONDS']].head(10),
                    use_container_width=True
                )
        else:
            st.info("No query performance data available for the selected time window.")
    
    # ========================================================================
    # TAB 4: RECOMMENDATIONS
    # ========================================================================
    with tab4:
        st.header("Optimization Recommendations")
        
        # Fetch data for analysis
        wh_metrics = get_warehouse_metrics(time_window)
        wh_load = get_warehouse_load(time_window)
        cost_by_workload = get_cost_by_workload(time_window)
        query_perf = get_query_performance(time_window)
        
        recommendations = []
        
        # Analyze queuing
        if not wh_load.empty:
            max_queued = wh_load['AVG_QUEUED_QUERIES'].max()
            if max_queued > 2:
                recommendations.append({
                    'priority': 'HIGH',
                    'category': 'Performance',
                    'issue': 'Significant query queuing detected',
                    'recommendation': f'Peak queued queries: {max_queued:.1f}. Consider scaling up warehouse size or enabling multi-cluster warehouses.',
                    'action': 'ALTER WAREHOUSE SFE_SP_WH SET WAREHOUSE_SIZE = LARGE;'
                })
        
        # Analyze idle time
        if not wh_metrics.empty:
            total_hours = len(wh_metrics)
            active_hours = len(wh_metrics[wh_metrics['EXECUTION_COUNT'] > 0])
            if total_hours > 0:
                utilization = (active_hours / total_hours) * 100
                if utilization < 30:
                    recommendations.append({
                        'priority': 'MEDIUM',
                        'category': 'Cost',
                        'issue': f'Low warehouse utilization ({utilization:.1f}%)',
                        'recommendation': 'Consider reducing auto-suspend timeout or consolidating workloads to reduce idle time.',
                        'action': 'ALTER WAREHOUSE SFE_SP_WH SET AUTO_SUSPEND = 30;'
                    })
        
        # Analyze slow queries
        if not query_perf.empty:
            slow_queries = query_perf[query_perf['EXECUTION_TIME_SECONDS'] > 300]
            if len(slow_queries) > 0:
                recommendations.append({
                    'priority': 'MEDIUM',
                    'category': 'Performance',
                    'issue': f'{len(slow_queries)} queries taking over 5 minutes',
                    'recommendation': 'Review slow queries for optimization opportunities (see Query Analysis tab).',
                    'action': 'Check query execution plans and consider adding clustering keys or materialized views.'
                })
        
        # Analyze cost distribution
        if not cost_by_workload.empty:
            workload_costs = cost_by_workload.groupby('WORKLOAD_TYPE')['TOTAL_CREDITS'].sum()
            if 'UNTAGGED' in workload_costs.index and workload_costs['UNTAGGED'] > 0:
                untagged_pct = (workload_costs['UNTAGGED'] / workload_costs.sum()) * 100
                recommendations.append({
                    'priority': 'LOW',
                    'category': 'Monitoring',
                    'issue': f'{untagged_pct:.1f}% of queries are untagged',
                    'recommendation': 'Add query tags to all forecasting workloads for better cost attribution.',
                    'action': "ALTER SESSION SET QUERY_TAG = 'WORKLOAD:type|PATH:approach';"
                })
        
        # Display recommendations
        if recommendations:
            for rec in sorted(recommendations, key=lambda x: {'HIGH': 0, 'MEDIUM': 1, 'LOW': 2}[x['priority']]):
                priority_color = {'HIGH': '🔴', 'MEDIUM': '🟡', 'LOW': '🟢'}[rec['priority']]
                
                with st.expander(f"{priority_color} [{rec['priority']}] {rec['category']}: {rec['issue']}"):
                    st.write(f"**Recommendation:** {rec['recommendation']}")
                    st.code(rec['action'], language='sql')
        else:
            st.success("✅ No major issues detected! Your forecasting workload is well-optimized.")
        
        # Best practices
        st.markdown("---")
        st.subheader("Best Practices Summary")
        
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown("""
            **Cost Optimization:**
            - Set aggressive auto-suspend (60s for batch workloads)
            - Use resource monitors to prevent budget overruns
            - Tag all queries for cost attribution
            - Review and optimize expensive queries monthly
            - Consider scaling down during off-peak hours
            """)
        
        with col2:
            st.markdown("""
            **Performance Optimization:**
            - Monitor for query queuing (scale up if needed)
            - Use appropriate warehouse sizes per workload
            - Enable multi-cluster for high concurrency
            - Implement incremental processing where possible
            - Cache frequently accessed data
            """)

if __name__ == "__main__":
    main()

