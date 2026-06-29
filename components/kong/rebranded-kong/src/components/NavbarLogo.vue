<template>
  <div class="brand-logo">
    <router-link
      :to="{ name: 'overview' }"
      title="go to overview page"
    >
      <img
        src="@/assets/logo.png?external"
        alt="Next G Cloud Logo"
      >
    </router-link>
  </div>
</template>

// Changes
<style scoped lang="scss">
.brand-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px 16px;
  width: 100%;
  box-sizing: border-box;

  a {
    display: flex;
    align-items: center;
    text-decoration: none;
  }

  img {
    max-height: 36px;
    max-width: 100%;
    width: auto;
    height: auto;
    object-fit: contain;
  }
}
</style>
