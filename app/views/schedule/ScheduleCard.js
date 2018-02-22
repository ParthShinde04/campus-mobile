import React from 'react';
import {
	View,
	Text,
	ListView,
	StyleSheet,
	TouchableHighlight,
	List,
	FlatList
} from 'react-native';

import { getClasses, getFinals } from './scheduleData';
import { FullScheduleListView } from './FullScheduleListView';
import ScrollCard from '../card/ScrollCard';
import Card from '../card/Card';
import Touchable from '../common/Touchable';
import logger from '../../util/logger';
import Icon from 'react-native-vector-icons/Ionicons';
import css from '../../styles/css';
import {
	COLOR_DGREY,
	COLOR_MGREY,
	COLOR_PRIMARY,
	COLOR_LGREY,
	COLOR_SECONDARY,
} from '../../styles/ColorConstants';
import {
	MAX_CARD_WIDTH,
} from '../../styles/LayoutConstants';

var scheduleData = getClasses();
var dataSource = new ListView.DataSource({ rowHasChanged: (r1, r2) => r1 !== r2 });

var ScheduleCard = () => {
	logger.ga('Card Mounted: Class Schedule');

	return (
		<Card 
			id='schedule'
			title='Class Schedule'>
			<ListView
                dataSource={dataSource.cloneWithRows(scheduleData)}
                renderRow={(rowData, sectionID, rowID, highlightRow) => (
					<ScheduleDay
						id={rowID}
						data={rowData}
					/>
                )}
            />
			<View style={css.sc_dayContainer}>
				<TouchableHighlight style={css.dc_locations_row_right} underlayColor={'rgba(200,200,200,.1)'} onPress={() => general.gotoNavigationApp(data.coords.lat, data.coords.lon)}>
					<View style={css.dl_dir_traveltype_container}>
						<Icon name="md-walk" size={32} color={COLOR_SECONDARY} />
					</View>
				</TouchableHighlight>
			</View>			
			<Touchable
				style={styles.fullScheduleButton}
				onPress={() => FullScheduleListView()}>
					<Text style={styles.more_label}>
						View Full Schedule
					</Text>
			</Touchable>
		</Card> 
	);

	// 	<Card
	// 		id='schedule'
	// 		title= {scheduleData['MO'][0].instructor_name} //'Class Schedule'
	// 		listData={scheduleData}
	// 		renderRow={
	// 			(rowData, sectionID, rowID, highlightRow) => (
	// 				(rowID !== 'SA' && rowID !== 'SU') ? (
	// 					<ScheduleDay
	// 						id={rowID}
	// 						data={rowData}
	// 					/>
	// 				) : (null)
	// 		)}
	// 		actionButton={null}
	// 		extraActions={null}
	// 		updateScroll={null}
	// 		lastScroll={null}
	// 	/>
	// );
};

var ScheduleDay = ({ id, data }) => (
	<View style={css.sc_dayContainer}>
		<Text style={css.sc_dayText}>
			{id}
		</Text>
		<DayList courseItems={data} />
	</View>
);

var DayList = ({ courseItems }) => (
	<ListView
		dataSource={dataSource.cloneWithRows(courseItems)}
		renderRow={(rowData, sectionID, rowID, highlightRow) => (
			<DayItem key={rowID} data={rowData} />
		)}
	/>
);

var DayItem = ({ data }) => (
	<View style={css.sc_dayRow}>
		<Text
			style={css.sc_courseText}
			numberOfLines={1}
		>
			{data.course_title}
		</Text>
		<Text style={css.sc_subText}>
			{data.meeting_type + ' ' + data.time_string + '\n'}
			{data.instructor_name + '\n'}
			{data.building + data.room}
		</Text>
	</View>
);

const styles = StyleSheet.create({
	more: { alignItems: 'center', justifyContent: 'center', padding: 6 },
	more_label: { fontSize: 20, color: COLOR_PRIMARY, fontWeight: '300' },
	specialEventsListView: { borderBottomWidth: 1, borderBottomColor: COLOR_MGREY },
	nextClassContainer: { flexGrow: 1, width: MAX_CARD_WIDTH },
	contentContainer: { flexShrink: 1, width: MAX_CARD_WIDTH },
	fullScheduleButton: { width: MAX_CARD_WIDTH, backgroundColor: COLOR_LGREY, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4, paddingVertical: 8, borderTopWidth: 1, borderBottomWidth: 1, borderColor: COLOR_MGREY },
});

export default ScheduleCard;
