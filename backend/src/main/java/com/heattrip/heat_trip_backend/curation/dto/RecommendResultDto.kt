package com.heattrip.heat_trip_backend.curation.dto

import com.fasterxml.jackson.annotation.JsonProperty

data class RecommendResultDto(
    val places: List<PlaceScoreDTO>? = null,
    val llm: LlmMeta? = null,
    val cat3FromLlm: List<String>? = null,
) {
    data class LlmMeta(
        @get:JsonProperty("schema_version")
        val schemaVersion: Int? = null,

        @get:JsonProperty("emotion_diagnosis")
        val emotionDiagnosis: String? = null,

        @get:JsonProperty("theme_name")
        val themeName: String? = null,

        @get:JsonProperty("theme_description")
        val themeDescription: String? = null,

        @get:JsonProperty("category_groups")
        val categoryGroups: List<CategoryGroup>? = null,

        val activities: List<Activity>? = null,
        val keywords: List<String>? = null,

        @get:JsonProperty("comfort_letter")
        val comfortLetter: String? = null,
    ) {
        data class CategoryGroup(
            @get:JsonProperty("group_name")
            val groupName: String? = null,
            val categories: List<String>? = null,
        )

        data class Activity(
            val title: String? = null,
            val description: String? = null,
        )
    }
}
