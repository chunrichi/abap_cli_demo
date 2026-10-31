(function () {
  'use strict';

  var RANGES = [7, 30, 90];
  var state = { days: 30, data: null, busy: false };
  var numberFmt = new Intl.NumberFormat('zh-CN');

  function $(id) {
    return document.getElementById(id);
  }

  function basePath() {
    var path = window.location.pathname;
    return path.charAt(path.length - 1) === '/' ? path : path + '/';
  }

  function fmtNumber(value) {
    return numberFmt.format(Number(value) || 0);
  }

  function fmtShortDate(iso) {
    return iso ? iso.slice(5).replace('-', '/') : '';
  }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function load() {
    state.busy = true;
    document.body.classList.add('loading');
    fetch(basePath() + 'api/stats?days=' + state.days, { headers: { Accept: 'application/json' } })
      .then(function (res) {
        if (!res.ok) {
          throw new Error('HTTP ' + res.status);
        }
        return res.json();
      })
      .then(function (data) {
        if (data.status !== 'ok') {
          throw new Error(data.message || '数据加载失败');
        }
        state.data = data;
        render(data);
      })
      .catch(renderError)
      .then(function () {
        state.busy = false;
        document.body.classList.remove('loading');
      });
  }

  function renderError(err) {
    $('kpis').innerHTML = '<div class="notice">数据加载失败：' + esc(err.message) + '</div>';
    $('chart-user-ops').innerHTML = '';
    $('chart-dev').innerHTML = '';
    $('top-tcodes').innerHTML = '';
    $('top-objects').innerHTML = '';
    $('foot').textContent = '';
  }

  function render(data) {
    renderKpis(data.kpi);
    renderChart($('chart-user-ops'), data.series, [
      { key: 'userOps', label: '用户操作', color: '#2563eb' }
    ]);
    renderChart($('chart-dev'), data.series, [
      { key: 'devObjects', label: '对象版本', color: '#0d9488' },
      { key: 'transports', label: '传输请求', color: '#d97706' }
    ]);
    renderRank($('top-tcodes'), data.topTcodes);
    renderRank($('top-objects'), data.topObjectTypes);
    $('foot').textContent =
      '数据窗口 ' + data.fromDate + ' ~ ' + data.toDate + ' · 生成于 ' + data.generatedAt;
  }

  function renderKpis(kpi) {
    var items = [
      ['用户操作次数', kpi.userOps, '变更文档'],
      ['活跃用户', kpi.activeUsers, '去重用户'],
      ['开发对象调整', kpi.devObjects, '版本记录'],
      ['传输请求', kpi.transports, '请求头'],
      ['当前在线用户', kpi.onlineUsers, 'USR41']
    ];
    $('kpis').innerHTML = items
      .map(function (item) {
        return (
          '<div class="kpi"><span class="kpi-label">' + item[0] + '</span>' +
          '<strong class="kpi-value">' + fmtNumber(item[1]) + '</strong>' +
          '<span class="kpi-note">' + item[2] + '</span></div>'
        );
      })
      .join('');
  }

  function niceMax(value) {
    if (value <= 4) {
      return 4;
    }
    var power = Math.pow(10, Math.floor(Math.log(value) / Math.LN10));
    var unit = power / 2;
    return Math.ceil(value / unit) * unit;
  }

  function renderChart(container, rows, series) {
    if (!rows || rows.length === 0) {
      container.innerHTML = '<div class="empty">暂无数据</div>';
      return;
    }

    var width = 640;
    var height = 240;
    var pad = { top: 14, right: 14, bottom: 30, left: 46 };
    var innerW = width - pad.left - pad.right;
    var innerH = height - pad.top - pad.bottom;
    var maxValue = 1;
    rows.forEach(function (row) {
      series.forEach(function (item) {
        maxValue = Math.max(maxValue, Number(row[item.key]) || 0);
      });
    });

    var top = niceMax(maxValue);
    var groupW = innerW / rows.length;
    var barW = Math.max(3, Math.min(series.length === 1 ? 22 : 14, (groupW * 0.72) / series.length));
    var groupInner = barW * series.length + (series.length - 1) * 2;
    var ticks = 4;
    var yOf = function (value) {
      return pad.top + innerH - (value / top) * innerH;
    };

    var svg = '<svg viewBox="0 0 ' + width + ' ' + height + '" role="img" aria-label="每日趋势">';
    for (var t = 0; t <= ticks; t++) {
      var tickValue = (top / ticks) * t;
      var y = yOf(tickValue);
      svg += '<line x1="' + pad.left + '" y1="' + y + '" x2="' + (width - pad.right) + '" y2="' + y + '" class="grid"/>';
      svg += '<text x="' + (pad.left - 8) + '" y="' + (y + 4) + '" class="axis-y">' + fmtNumber(Math.round(tickValue)) + '</text>';
    }

    var labelEvery = Math.max(1, Math.ceil(rows.length / 7));
    rows.forEach(function (row, index) {
      var groupX = pad.left + groupW * index + (groupW - groupInner) / 2;
      series.forEach(function (item, seriesIndex) {
        var value = Number(row[item.key]) || 0;
        var barHeight = value === 0 ? 0 : Math.max(2, (value / top) * innerH);
        var x = groupX + seriesIndex * (barW + 2);
        if (barHeight > 0) {
          svg +=
            '<rect x="' + x.toFixed(1) + '" y="' + (pad.top + innerH - barHeight).toFixed(1) +
            '" width="' + barW.toFixed(1) + '" height="' + barHeight.toFixed(1) +
            '" rx="2" fill="' + item.color + '" opacity="0.92"><title>' +
            row.date + ' ' + item.label + '：' + fmtNumber(value) + '</title></rect>';
        }
      });
      if (index % labelEvery === 0 || index === rows.length - 1) {
        svg +=
          '<text x="' + (pad.left + groupW * index + groupW / 2).toFixed(1) +
          '" y="' + (height - 10) + '" class="axis-x">' + fmtShortDate(row.date) + '</text>';
      }
    });
    svg += '</svg>';

    svg += '<div class="legend">';
    series.forEach(function (item) {
      svg += '<span class="legend-item"><i style="background:' + item.color + '"></i>' + item.label + '</span>';
    });
    svg += '</div>';
    container.innerHTML = svg;
  }

  function renderRank(list, items) {
    if (!items || items.length === 0) {
      list.innerHTML = '<li class="empty">暂无数据</li>';
      return;
    }
    var max = 1;
    items.forEach(function (item) {
      max = Math.max(max, item.count);
    });
    list.innerHTML = items
      .map(function (item) {
        return (
          '<li><span class="rank-name">' + esc(item.name) + '</span>' +
          '<span class="rank-bar"><i style="width:' + ((item.count / max) * 100).toFixed(1) + '%"></i></span>' +
          '<span class="rank-count">' + fmtNumber(item.count) + '</span></li>'
        );
      })
      .join('');
  }

  $('range').addEventListener('click', function (event) {
    var button = event.target.closest('button[data-days]');
    if (!button || state.busy) {
      return;
    }
    var days = Number(button.getAttribute('data-days'));
    if (RANGES.indexOf(days) === -1 || days === state.days) {
      return;
    }
    state.days = days;
    var buttons = document.querySelectorAll('#range button');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].classList.toggle('active', buttons[i] === button);
    }
    load();
  });

  $('refresh').addEventListener('click', function () {
    if (!state.busy) {
      load();
    }
  });

  load();
})();
