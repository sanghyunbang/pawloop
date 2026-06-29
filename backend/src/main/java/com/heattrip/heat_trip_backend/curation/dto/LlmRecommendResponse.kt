package com.heattrip.heat_trip_backend.curation.dto

import com.fasterxml.jackson.annotation.JsonProperty

data class LlmRecommendResponse(
    @field:JsonProperty("schema_version")
    @param:JsonProperty("schema_version")
    val schemaVersion: Int = 0,

    @field:JsonProperty("emotion_diagnosis")
    @param:JsonProperty("emotion_diagnosis")
    val emotionDiagnosis: String? = null,

    @field:JsonProperty("theme_name")
    @param:JsonProperty("theme_name")
    val themeName: String? = null,

    @field:JsonProperty("theme_description")
    @param:JsonProperty("theme_description")
    val themeDescription: String? = null,

    @field:JsonProperty("category_groups")
    @param:JsonProperty("category_groups")
    val categoryGroups: List<CategoryGroup>? = null,

    val activities: List<Activity>? = null,
    val keywords: List<String>? = null,

    @field:JsonProperty("comfort_letter")
    @param:JsonProperty("comfort_letter")
    val comfortLetter: String? = null
) {
    data class CategoryGroup(
        @field:JsonProperty("group_name")
        @param:JsonProperty("group_name")
        val groupName: String? = null,
        val categories: List<String>? = null
    )

    data class Activity(
        val title: String? = null,
        val description: String? = null
    )
}
