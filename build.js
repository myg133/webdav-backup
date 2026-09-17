#!/usr/bin/env node
const path = require('path');
const { appTasks } = require('@ohos/hvigor-ohos-plugin');

appTasks.forEach(task => {
  task.map(context => {
    context.rootPath = path.resolve(__dirname, '.');
    return context;
  });
});