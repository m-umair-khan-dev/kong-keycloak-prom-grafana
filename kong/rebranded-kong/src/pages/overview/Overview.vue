<template>
  <section class="info-container">
    <KCard
      v-for="infoItem in info"
      :key="infoItem.title"
      :title="infoItem.title"
    >
      <ul class="info-list">
        <li
          v-for="item in infoItem.items"
          :key="item.label"
          class="info-item"
        >
          <label>{{ item.label }}</label>
          <KBadge
            max-width="300px"
            :tooltip="String(item.value)"
            truncation-tooltip
          >
            {{ item.value }}
          </KBadge>
        </li>
      </ul>
    </KCard>
  </section>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from '@/composables/useI18n'
import { useInfoStore } from '@/stores/info'

defineOptions({
  name: 'ManagerOverview',
})

const { t } = useI18n()
const infoStore = useInfoStore()

const config = computed(() => ({
  ...infoStore.infoConfig,
  kongVersion: infoStore.kongVersion,
  kongEdition: infoStore.kongEdition,
  hostname: infoStore.info.hostname,
}))
const info = computed(() => {
  const guiListeners = config.value.admin_gui_listeners
  const nonSslGuiListener = guiListeners?.find?.(listener => !listener.ssl)
  const sslGuiListener = guiListeners?.find?.(listener => listener.ssl)
  const proxyListeners = config.value.proxy_listeners
  const nonSslProxyListener = proxyListeners?.find?.(listener => !listener.ssl)
  const sslProxyListener = proxyListeners?.find?.(listener => listener.ssl)

  return [
    {
      title: t('overview.info.gateway.title'),
      items: [
        {
          label: t('overview.info.gateway.edition'),
          value: config.value.kongEdition,
        },
        {
          label: t('overview.info.gateway.version'),
          value: config.value.kongVersion,
        },
      ],
    },
    {
      title: t('overview.info.node.title'),
      items: [
        {
          label: t('overview.info.node.address'),
          value: config.value.admin_listen?.[0] ?? '--',
        },
        {
          label: t('overview.info.node.hostname'),
          value: config.value.hostname ?? '--',
        },
      ],
    },
    {
      title: t('overview.info.port.title'),
      items: [
        {
          label: t('overview.info.port.port'),
          value: nonSslGuiListener?.port ?? '--',
        },
        {
          label: t('overview.info.port.ssl'),
          value: sslGuiListener?.port ?? '--',
        },
        {
          label: t('overview.info.port.proxy'),
          value: nonSslProxyListener?.port ?? '--',
        },
        {
          label: t('overview.info.port.proxy.ssl'),
          value: sslProxyListener?.port ?? '--',
        },
      ],
    },
    ...(
      config.value.database === 'postgres'
        ? [
          {
            title: t('overview.info.datastore.title'),
            items: [
              {
                label: t('overview.info.datastore.type'),
                value: config.value.database,
              },
              {
                label: t('overview.info.datastore.user'),
                value: config.value.pg_user,
              },
              {
                label: t('overview.info.datastore.host'),
                value: config.value.pg_host,
              },
              {
                label: t('overview.info.datastore.port'),
                value: config.value.pg_port,
              },
              {
                label: t('overview.info.datastore.ssl'),
                value: config.value.pg_ssl,
              },
            ],
          },
        ]
        : []
    ),
  ]
})
</script>

<style scoped lang="scss">
$card-spacing: 32px;

.info-container {
  display: grid;
  grid-template-columns: 1fr 1fr;
  grid-gap: $card-spacing;
  margin-bottom: $card-spacing;
}
.info-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.info-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 0;

  &:not(:last-child) {
    border-bottom: 1px solid $kui-color-border;
  }

  label {
    color: $kui-color-text-neutral-stronger;
    font-size: 14px;
    font-weight: bold;
    margin: 0;
  }
}
</style>
