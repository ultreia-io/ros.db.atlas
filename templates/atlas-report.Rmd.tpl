---
title: "{{title}}"
author: "{{author}}"
date: "{{timestamp}}"
output:
  html_document:
    mathjax: null
    number_sections: false
    toc: true
    toc_float:
      collapsed: false
    anchor_sections: true
    self_contained: true
---

<style>
{{{style}}}
</style>

<script>
{{{report_script}}}
</script>

{{{analytics}}}

{{#has_logo}}<img src="{{logo}}" alt="IOTC logo" class="atlas-logo">{{/has_logo}}

# Abstract

{{abstract}}

{{{body}}}
