package com.lucse62b.lucse62b

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class CsePortalWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cse_portal_widget).apply {
                setTextViewText(
                    R.id.widget_class_label,
                    widgetData.getString("class_label", "NEXT CLASS"),
                )
                setTextViewText(
                    R.id.widget_class_title,
                    widgetData.getString("class_title", "No upcoming class"),
                )
                setTextViewText(
                    R.id.widget_class_details,
                    widgetData.getString(
                        "class_details",
                        "Open the app to refresh your routine",
                    ),
                )
                setTextViewText(
                    R.id.widget_bus_status,
                    widgetData.getString("bus_status", "No upcoming bus"),
                )
                setTextViewText(
                    R.id.widget_deadline,
                    widgetData.getString("deadline", "No upcoming deadline"),
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
