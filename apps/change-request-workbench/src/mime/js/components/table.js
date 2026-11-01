/**
 * components/table.js — 数据表格与排序绑定。
 * 服务端分页 / 排序：点击表头把 sort / order 写入 URL，由页面重新拉取。
 */

import * as ui from '../ui.js';

function cssWidth(col) {
  if (col.width === undefined || col.width === null) return '';
  return typeof col.width === 'number' ? col.width + 'px' : String(col.width);
}

function colgroupHtml(columns) {
  return `<colgroup>${columns
    .map((col) => {
      if (col.flex) return '<col>';
      const width = cssWidth(col);
      return `<col style="width:${ui.esc(width || '140px')}">`;
    })
    .join('')}</colgroup>`;
}

/** 固定列宽表的最小宽度 = 固定列宽之和 + 弹性列最小宽（避免 1440 内被过度挤压）。 */
function fixedMinWidth(columns) {
  let total = 0;
  columns.forEach((col) => {
    if (col.flex) {
      total += Number(col.minWidth) || 220;
      return;
    }
    const width = cssWidth(col);
    total += parseInt(width, 10) || 140;
  });
  return total;
}

/**
 * @param {object} options
 *  - columns: [{ key, label, sortable, align:'right', width, flex, ellipsis, className, render(row) }]
 *  - rows: [[...]]
 *  - loading / error / empty: 渲染态
 *  - emptyOptions: 透传给 ui.emptyPanel
 *  - sortKey / sortOrder: 当前排序
 *  - rowHref(row): 行点击跳转 hash
 *  - rowClass(row)
 */
export function table(options = {}) {
  const columns = options.columns || [];
  const rows = options.rows || [];
  const fixed = columns.some((col) => col.flex) || options.fixed === true;
  if (options.loading) {
    return `<div class="table-wrap">${ui.loadingPanel(options.loadingText || '正在加载…')}</div>`;
  }
  if (options.error) {
    return `<div class="table-wrap">${ui.errorPanel(options.error)}</div>`;
  }
  if (!rows.length) {
    return `<div class="table-wrap">${ui.emptyPanel(options.emptyOptions || {})}</div>`;
  }
  const head = columns
    .map((col) => {
      const classes = [col.align === 'right' ? 'num' : '', col.className || ''].filter(Boolean).join(' ');
      const sortable = col.sortable ? ' sortable' : '';
      let dir = '';
      if (col.sortable && options.sortKey === col.key) {
        dir = `<span class="sort-dir">${options.sortOrder === 'asc' ? '↑' : '↓'}</span>`;
      }
      const attr = col.sortable ? ` data-sort="${ui.esc(col.key)}"` : '';
      const widthCss = cssWidth(col);
      const width = widthCss ? ` style="width:${ui.esc(widthCss)}"` : '';
      return `<th class="${classes}${sortable}"${attr}${width}>${ui.esc(col.label)}${dir}</th>`;
    })
    .join('');
  const body = rows
    .map((row) => {
      const href = typeof options.rowHref === 'function' ? options.rowHref(row) : '';
      const rowClass = typeof options.rowClass === 'function' ? options.rowClass(row) : '';
      const rowClasses = [href ? 'clickable' : '', rowClass || ''].filter(Boolean).join(' ');
      const cells = columns
        .map((col) => {
          const classes = [col.align === 'right' ? 'num' : '', col.className || ''].filter(Boolean).join(' ');
          let content = typeof col.render === 'function' ? col.render(row) : ui.safe(row[col.key]);
          if (col.ellipsis) content = `<div class="cell-clip">${content}</div>`;
          return `<td class="${classes}">${content}</td>`;
        })
        .join('');
      return `<tr${href ? ` data-href="${ui.esc(href)}"` : ''}${
        rowClasses ? ` class="${ui.esc(rowClasses)}"` : ''
      }>${cells}</tr>`;
    })
    .join('');
  const tableClass = fixed ? 'data fixed' : 'data';
  const tableStyle = fixed ? ` style="min-width:${fixedMinWidth(columns)}px"` : '';
  return `<div class="table-wrap"><table class="${tableClass}"${tableStyle}>${
    fixed ? colgroupHtml(columns) : ''
  }<thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

/** 表头排序：点击 sortable 表头切换 asc/desc 并写回 URL。 */
export function bindSort(root, ctx, options = {}) {
  ui.bindAll(root, 'th[data-sort]', 'click', (event, el) => {
    const key = el.getAttribute('data-sort');
    if (!key) return;
    const currentSort = options.sortKey || '';
    const currentOrder = options.sortOrder || 'desc';
    if (currentSort === key) {
      ctx.setQuery({ sort: key, order: currentOrder === 'desc' ? 'asc' : 'desc' });
    } else {
      ctx.setQuery({ sort: key, order: 'desc' });
    }
  });
}

/** 行点击跳转（忽略按钮 / 链接 / 表单控件内部的点击）。 */
export function bindRowLinks(root, ctx) {
  ui.bindAll(root, 'tr[data-href]', 'click', (event, el) => {
    const target = event.target;
    if (target && typeof target.closest === 'function') {
      if (target.closest('a, button, input, select, textarea, label')) return;
    }
    const href = el.getAttribute('data-href');
    if (href) ctx.navigate(href);
  });
}

/** 分页条 + 绑定（page / size 写入 URL）。 */
export function pager(root, ctx, pageData, options = {}) {
  if (!pageData || options.hideIfEmpty) {
    if (!pageData || !pageData.total) return '';
  }
  const total = Number(pageData.total) || 0;
  if (total === 0) return '';
  return ui.pagination({
    page: pageData.page,
    pageSize: pageData.pageSize,
    total
  });
}

export function bindPager(root, ctx) {
  ui.bindPager(root, (change) => {
    const patch = {};
    if (change.page !== undefined) patch.page = change.page;
    if (change.pageSize !== undefined) patch.size = change.pageSize;
    ctx.setQuery(patch);
  });
}
